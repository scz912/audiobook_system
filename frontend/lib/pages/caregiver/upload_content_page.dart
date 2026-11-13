import 'dart:io';

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../audio/audio_safety.dart';
import '../../i18n/app_strings.dart';
import '../../i18n/i18n.dart';
import '../../models/audiobook.dart';
import '../../models/content_item.dart';
import '../../services/api_service.dart';
import '../../services/database_service.dart';
import '../../state/language_state.dart';
import '../../theme/app_colors.dart';
import '../../models/music_track.dart';
import '../../widgets/adaptive_row.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/bgm_picker_sheet.dart';
import '../../widgets/soft_card.dart';
import '../../widgets/soft_chip.dart';
import '../../widgets/guide.dart';
import '../../widgets/paige_mascot.dart';
import '../../widgets/whole_words_text.dart';

// Interactive audiobook forms, editor cards, steppers and the guide.
part 'upload_interactive.dart';

// One page being authored in the manual storybook builder.
class _PageDraft {
  final TextEditingController text = TextEditingController();
  String? imagePath;
  /* Where this page starts in the recording, in ms. Set by the boundary
     editor; null on page 1 (auto = 0) and on pages not marked yet. */
  int? audioStartMs;
  void dispose() => text.dispose();
}

enum _Mode { write, ai }

/* Colours for this page: a pastel tint per section, and a stronger colour
   for each section's icon, so the long form is easy to scan. */
class _Tint {
  _Tint._();
  static const details = Color(0xFFEFF5FF); // blue
  static const cover = Color(0xFFFFF0F4); // pink
  static const language = Color(0xFFEEF8F1); // mint
  static const page = Color(0xFFF6F1FF); // lavender
  static const music = Color(0xFFFFF7E3); // butter
  static const ai = Color(0xFFF3EEFF); // violet

  static const blue = Color(0xFF5B8DEF);
  static const pink = Color(0xFFEC6A8F);
  static const mint = Color(0xFF3FAF7A);
  static const yellow = Color(0xFFE9A800);
  static const peach = Color(0xFFF08A4B);
  static const lavender = Color(0xFF8B6CE0);
}

/* Linear = read straight through. Interactive = some pages pause and let
   the child pick an answer that changes the next page. */
enum _BookFormat { linear, interactive }

class UploadContentPage extends StatefulWidget {
  const UploadContentPage({super.key, this.interactive = false});

  // Open on the Interactive format (from the library's Interactive shelf).
  final bool interactive;

  @override
  State<UploadContentPage> createState() => _UploadContentPageState();
}

class _UploadContentPageState extends State<UploadContentPage> {
  _Mode _mode = _Mode.write;
  late _BookFormat _format =
      widget.interactive ? _BookFormat.interactive : _BookFormat.linear;

  // Interactive "write" pages (kept apart from the linear pages).
  final List<_InteractivePageDraft> _interactiveDrafts = [
    _InteractivePageDraft(),
  ];

  // Interactive AI settings. Pages must be a fixed number for the 1-in-4 cap.
  int _aiInteractions = 1;
  int _aiSplits = 0;

  // Manual ("write") form
  final _titleCtrl = TextEditingController();
  final _topicCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  String _difficulty = 'Easy';
  bool _submitting = false;

  // Manual storybook pages (text + optional image each) + cover.
  final ImagePicker _picker = ImagePicker();
  String? _coverPath;
  final List<_PageDraft> _pageDrafts = [_PageDraft()];

  // Optional whole-book recording. When set, the player follows the audio
  // and flips pages by each page's word share.
  String? _audioPath;

  // Language for the manual storybook. null = use the app language; 'en' /
  // 'ms' override it.
  String? _manualLanguage;

  // Music for write mode (must pick one when on).
  bool _writeBgmEnabled = false;
  MusicTrack? _writeBgmTrack;
  int _writeBgmVolume = 30;

  // Music for AI mode (null = let the backend pick when on).
  bool _aiBgmEnabled = false;
  MusicTrack? _aiBgmTrack;
  int _aiBgmVolume = 30;

  // AI ("generate") form
  final _aiTopicCtrl = TextEditingController();
  final _aiBaseTextCtrl = TextEditingController();
  String _aiDifficulty = 'Easy';
  String _aiPages = 'Auto';
  bool _aiGenerateImage = true;
  bool _generating = false;
  // Language Gemini writes the story in. Defaults to the app language; the
  // caregiver can override it.
  String? _aiLanguage;

  static const _pageOptions = ['Auto', '4', '6', '8', '10', '12'];
  static const _interactivePageOptions = ['4', '6', '8', '10', '12'];
  static const _guideSeenKey = 'interactive_write_guide_seen';

  /* Paige's guides for this page, like the app's first-time tour: one
     short line at a time with the spotlight on what she means. One for the
     page (first visit), one for interactive books. */
  final _formatKey = GlobalKey();
  final _modeKey = GlobalKey();
  final _firstPageKey = GlobalKey();
  GuideController? _guide;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await GuideMemory.isDone('upload') || !mounted) return;
      await GuideMemory.markDone('upload');
      _startPageGuide();
    });
  }

  void _startPageGuide() => _startGuide([
        const GuideStep('guide.up_hi'),
        GuideStep('guide.up_format', target: _formatKey, onStart: () => _reveal(_formatKey)),
        GuideStep('guide.up_mode', target: _modeKey, onStart: () => _reveal(_modeKey)),
        const GuideStep('guide.up_done', celebrate: true),
      ]);

  /* Paige in the header replays the guide: how interactive books work
     when making one, otherwise the tour of this page. */
  void _replayGuide() {
    if (_guide != null) return;
    if (_format == _BookFormat.interactive) {
      _startInteractiveGuide();
    } else {
      _startPageGuide();
    }
  }

  void _startGuide(List<GuideStep> steps) {
    final guide = GuideController(
      steps: steps,
      openTab: (_) {},
      onFinish: () {
        if (mounted) setState(() => _guide = null);
      },
    );
    setState(() => _guide = guide);
    guide.start();
  }

  // Scroll so what Paige points at is on screen.
  void _reveal(GlobalKey key) {
    final c = key.currentContext;
    if (c != null) {
      Scrollable.ensureVisible(c,
          duration: const Duration(milliseconds: 300), alignment: 0.2);
    }
  }

  /* How interactive books work. In Write mode it rings the first page
     card; from the AI form there are no pages to point at. */
  void _startInteractiveGuide() {
    final onPage = _format == _BookFormat.interactive && _mode == _Mode.write;
    GuideStep onCard(String key) => GuideStep(key,
        target: onPage ? _firstPageKey : null,
        onStart: onPage ? () => _reveal(_firstPageKey) : null);
    _startGuide([
      const GuideStep('guide.ia_hi'),
      onCard('guide.ia_switch'),
      onCard('guide.ia_choices'),
      onCard('guide.ia_answer'),
      onCard('guide.ia_split'),
      const GuideStep('guide.ia_done', celebrate: true),
    ]);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _topicCtrl.dispose();
    _tagsCtrl.dispose();
    for (final p in _pageDrafts) {
      p.dispose();
    }
    for (final p in _interactiveDrafts) {
      p.dispose();
    }
    _aiTopicCtrl.dispose();
    _aiBaseTextCtrl.dispose();
    super.dispose();
  }

  // manual storybook builder

  Future<void> _pickImage(void Function(String path) onPicked) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 85,
      );
      if (file != null) setState(() => onPicked(file.path));
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context.trRead('upload.err_pick_image').replaceAll('{error}', '$e'), context: context);
      }
    }
  }

  Future<void> _pickAudio() async {
    try {
      /* By extension rather than FileType.audio: on iPhone that opens the
         Apple Music library, which can't reach files a caregiver recorded
         or downloaded. These are the types the backend accepts. */
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'],
        allowMultiple: false,
        withData: false,
      );
      final path = result?.files.single.path;
      if (path != null) {
        setState(() {
          _audioPath = path;
          // A new recording clears the old page marks - they no longer fit.
          for (final d in _pageDrafts) {
            d.audioStartMs = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context.trRead('upload.err_pick_audio').replaceAll('{error}', '$e'), context: context);
      }
    }
  }

  void _addPage() => setState(() => _pageDrafts.add(_PageDraft()));

  void _removePage(int index) {
    if (_pageDrafts.length <= 1) return;
    setState(() {
      _pageDrafts.removeAt(index).dispose();
    });
  }

  /* FR5: before saving, warn if the background music is set loud enough to
     compete with the narration, and offer a one-tap fix. Returns false if
     the caregiver chose to go back and change it. */
  Future<bool> _confirmMusicLevel({
    required bool enabled,
    required int volume,
    required VoidCallback lower,
  }) async {
    if (!enabled || !AudioSafety.bgmTooLoud(volume)) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('upload.bgm_loud_title')),
        content: Text(ctx
            .tr('upload.bgm_loud_body')
            .replaceAll('{level}', '$volume')
            .replaceAll('{fix}', '${AudioSafety.bgmRecommended}')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('back'),
            child: Text(ctx.tr('upload.bgm_loud_back')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('keep'),
            child: Text(ctx.tr('upload.bgm_loud_keep')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('lower'),
            child: Text(ctx
                .tr('upload.bgm_loud_fix')
                .replaceAll('{fix}', '${AudioSafety.bgmRecommended}')),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    if (choice == 'lower') {
      setState(lower);
      return true;
    }
    return choice == 'keep';
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      AppSnackbar.warning(context.trRead('upload.err_title_required'), context: context);
      return;
    }
    final hasContent = _pageDrafts.any((p) =>
        p.text.text.trim().isNotEmpty || p.imagePath != null);
    if (!hasContent) {
      AppSnackbar.warning(context.trRead('upload.err_need_page'), context: context);
      return;
    }
    if (_writeBgmEnabled && _writeBgmTrack == null) {
      AppSnackbar.warning(context.trRead('upload.err_need_track'), context: context);
      return;
    }
    if (!await _confirmMusicLevel(
        enabled: _writeBgmEnabled,
        volume: _writeBgmVolume,
        lower: () => _writeBgmVolume = AudioSafety.bgmRecommended)) {
      return;
    }
    if (!mounted) return;

    setState(() => _submitting = true);

    // 1) Create the book (with optional cover) and get its id.
    final joinedText = _pageDrafts
        .map((p) => p.text.text.trim())
        .where((t) => t.isNotEmpty)
        .join('\n\n');
    final language =
        _manualLanguage ?? context.read<LanguageState>().code;
    final created = await DatabaseService.createContentWithCover(
      title: _titleCtrl.text.trim(),
      topic: _topicCtrl.text.trim(),
      difficulty: _difficulty,
      tags: _tagsCtrl.text.trim(),
      type: _audioPath != null ? 'Audio' : 'Text',
      contentText: joinedText,
      coverImagePath: _coverPath,
      audioFilePath: _audioPath,
      language: language,
      trackId: _writeBgmEnabled ? _writeBgmTrack?.trackId : null,
      bgmVolume: _writeBgmVolume,
    );

    if (!mounted) return;
    if (!created.success || created.data is! ContentItem) {
      setState(() => _submitting = false);
      AppSnackbar.error(created.message, context: context);
      return;
    }

    final audiobookId = (created.data as ContentItem).audiobookId;
    if (audiobookId == null) {
      setState(() => _submitting = false);
      AppSnackbar.error(context.trRead('upload.err_no_id'), context: context);
      return;
    }

    // 2) Add each page (text + optional image + optional page mark).
    // Page 1 always starts at 0, so we send null for it; later page marks
    // come from the boundary editor.
    var pageNo = 1;
    for (final draft in _pageDrafts) {
      final text = draft.text.text.trim();
      if (text.isEmpty && draft.imagePath == null) continue;
      final pageResp = await DatabaseService.addAudiobookPage(
        audiobookId: audiobookId,
        pageNumber: pageNo,
        text: text,
        imagePath: draft.imagePath,
        audioStartMs: pageNo == 1 ? null : draft.audioStartMs,
      );
      if (!pageResp.success && mounted) {
        AppSnackbar.warning(
            context
                .trRead('upload.err_page_failed')
                .replaceAll('{n}', '$pageNo')
                .replaceAll('{message}', pageResp.message),
            context: context);
      }
      pageNo++;
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    AppSnackbar.success(context.trRead('upload.saved'), context: context);
    Navigator.of(context).pop();
  }

  // AI generate

  Future<void> _generateAi() async {
    final topic = _aiTopicCtrl.text.trim();
    if (topic.isEmpty) {
      AppSnackbar.warning(context.trRead('upload.err_topic_required'), context: context);
      return;
    }
    if (!await _confirmMusicLevel(
        enabled: _aiBgmEnabled,
        volume: _aiBgmVolume,
        lower: () => _aiBgmVolume = AudioSafety.bgmRecommended)) {
      return;
    }
    if (!mounted) return;
    setState(() => _generating = true);
    final language =
        _aiLanguage ?? context.read<LanguageState>().code; // app language by default
    final interactive = _format == _BookFormat.interactive;
    final ApiResponse resp = await DatabaseService.generateAiContent(
      topic: topic,
      difficulty: _aiDifficulty,
      sourceText: _aiBaseTextCtrl.text.trim(),
      generateImage: _aiGenerateImage,
      pageCount: _aiPages == 'Auto' ? null : int.tryParse(_aiPages),
      includeBgm: _aiBgmEnabled,
      trackId: _aiBgmTrack?.trackId, // null = backend picks when music is on
      bgmVolume: _aiBgmVolume,
      language: language,
      interactive: interactive,
      interactionCount: _aiInteractions,
      splitCount: _aiSplits,
    );
    if (!mounted) return;
    setState(() => _generating = false);

    if (resp.success && resp.data is ContentItem) {
      await _showResultDialog(resp.data as ContentItem, resp.message);
      if (mounted) Navigator.of(context).pop();
    } else {
      AppSnackbar.error(resp.message, context: context);
    }
  }

  Future<void> _showResultDialog(ContentItem item, String message) {
    final processing = item.status == 'processing';
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: processing
                            ? AppColors.softPeach
                            : AppColors.iconCircleGreen,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        processing
                            ? Icons.hourglass_top_rounded
                            : Icons.check_rounded,
                        size: 24,
                        color: processing
                            ? AppColors.textPrimary
                            : AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.tr(processing ? 'upload.creating' : 'upload.created'),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (item.coverImage != null && item.coverImage!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      item.coverImage!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      cacheWidth: 600,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(item.title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    item.contentText ?? item.description ?? '',
                    style: const TextStyle(height: 1.5),
                  ),
                ),
                const SizedBox(height: 10),
                Text(message,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.tr('common.done'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // interactive audiobooks

  void _setFormat(_BookFormat f) {
    _format = f;
    // Interactive AI books need a fixed length for the 1-in-4 cap.
    if (f == _BookFormat.interactive && _aiPages == 'Auto') _aiPages = '8';
    _clampAiInteractions();
  }

  void _setAiPages(String p) {
    _aiPages = p;
    _clampAiInteractions();
  }

  // Keep interactions within 1..floor(pages / 4) and splits within 0..interactions.
  void _clampAiInteractions() {
    final cap = (int.tryParse(_aiPages) ?? 8) ~/ 4;
    _aiInteractions = _aiInteractions.clamp(1, cap < 1 ? 1 : cap);
    if (_aiSplits > _aiInteractions) _aiSplits = _aiInteractions;
  }

  // Show the guide automatically the first time Interactive + Write opens.
  Future<void> _maybeShowInteractiveGuide() async {
    if (_format != _BookFormat.interactive || _mode != _Mode.write) return;
    // The page guide is still running; this one waits for another time.
    if (_guide != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_guideSeenKey) ?? false) return;
      await prefs.setBool(_guideSeenKey, true);
    } catch (_) {
      return;
    }
    if (mounted) _startInteractiveGuide();
  }

  void _addInteractivePage() =>
      setState(() => _interactiveDrafts.add(_InteractivePageDraft()));

  void _removeInteractivePage(int index) {
    if (_interactiveDrafts.length <= 1) return;
    final removed = _interactiveDrafts[index];
    setState(() => _interactiveDrafts.removeAt(index));
    // Dispose after the frame, once its text fields are gone.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  /* First page number of each draft. A question page also owns the
     response page after it, so it uses up 2 numbers. */
  List<int> _interactivePageNumbers() {
    final out = <int>[];
    var n = 1;
    for (final d in _interactiveDrafts) {
      out.add(n);
      n += d.interactive ? 2 : 1;
    }
    return out;
  }

  // The first thing that would stop the book from working, or null.
  String? _interactiveProblem() {
    if (!_interactiveDrafts.any((d) => d.interactive)) {
      return context.trRead('upload.err_no_interactive');
    }
    final numbers = _interactivePageNumbers();
    String at(String key, int page) =>
        context.trRead(key).replaceAll('{n}', '$page');
    for (var i = 0; i < _interactiveDrafts.length; i++) {
      final d = _interactiveDrafts[i];
      final n = numbers[i];
      if (!d.interactive) continue;
      if (d.text.text.trim().isEmpty) {
        return at('upload.err_question_text', n);
      }
      final choices = d.choiceTexts;
      if (choices.length < 2) return at('upload.err_two_choices', n);
      if (choices.map((c) => c.toLowerCase()).toSet().length !=
          choices.length) {
        return at('upload.err_same_choice', n);
      }
      if (d.split) {
        for (var b = 0; b < 2; b++) {
          final branch = d.branches[b];
          if (branch.text.text.trim().isEmpty && branch.imagePath == null) {
            return at('upload.err_branch_page', n + 1).replaceAll('{choice}', choices[b]);
          }
        }
      } else {
        final response = d.response.text.text;
        if (response.trim().isEmpty) {
          return at('upload.err_response_page', n + 1);
        }
        if (!response.contains(AudiobookPage.choiceToken)) {
          return at('upload.err_placeholder', n + 1);
        }
      }
    }
    return null;
  }

  Future<void> _submitInteractive() async {
    if (_titleCtrl.text.trim().isEmpty) {
      AppSnackbar.warning(context.trRead('upload.err_title_required'), context: context);
      return;
    }
    final problem = _interactiveProblem();
    if (problem != null) {
      AppSnackbar.warning(problem, context: context);
      return;
    }
    if (_writeBgmEnabled && _writeBgmTrack == null) {
      AppSnackbar.warning(context.trRead('upload.err_need_track'), context: context);
      return;
    }
    if (!await _confirmMusicLevel(
        enabled: _writeBgmEnabled,
        volume: _writeBgmVolume,
        lower: () => _writeBgmVolume = AudioSafety.bgmRecommended)) {
      return;
    }
    if (!mounted) return;

    setState(() => _submitting = true);

    // Main path only (first version of each split), for search + music matching.
    final joinedText = [
      for (final d in _interactiveDrafts) ...[
        d.text.text.trim(),
        if (d.interactive)
          (d.split ? d.branches.first : d.response).text.text.trim(),
      ],
    ].where((t) => t.isNotEmpty).join('\n\n');

    final created = await DatabaseService.createContentWithCover(
      title: _titleCtrl.text.trim(),
      topic: _topicCtrl.text.trim(),
      difficulty: _difficulty,
      tags: _tagsCtrl.text.trim(),
      type: 'Text',
      contentText: joinedText,
      coverImagePath: _coverPath,
      language: _manualLanguage ?? context.read<LanguageState>().code,
      trackId: _writeBgmEnabled ? _writeBgmTrack?.trackId : null,
      bgmVolume: _writeBgmVolume,
      bookFormat: 'interactive',
    );

    if (!mounted) return;
    final audiobookId =
        created.data is ContentItem ? (created.data as ContentItem).audiobookId : null;
    if (!created.success || audiobookId == null) {
      setState(() => _submitting = false);
      AppSnackbar.error(
          created.success ? context.trRead('upload.err_no_id') : created.message,
          context: context);
      return;
    }

    // Save the pages. A split page is 2 rows with the same page number.
    var pageNo = 1;
    final failed = <int>[];
    Future<void> add(String text, String? image,
        {List<String>? choices, bool isSplit = false, int? branch}) async {
      final r = await DatabaseService.addAudiobookPage(
        audiobookId: audiobookId,
        pageNumber: pageNo,
        text: text,
        imagePath: image,
        choices: choices,
        isSplit: isSplit,
        branchIndex: branch,
      );
      if (!r.success && !failed.contains(pageNo)) failed.add(pageNo);
    }

    for (final d in _interactiveDrafts) {
      final text = d.text.text.trim();
      if (!d.interactive) {
        if (text.isEmpty && d.imagePath == null) continue;
        await add(text, d.imagePath);
        pageNo++;
        continue;
      }
      await add(text, d.imagePath, choices: d.choiceTexts, isSplit: d.split);
      pageNo++;
      if (d.split) {
        for (var b = 0; b < 2; b++) {
          await add(d.branches[b].text.text.trim(), d.branches[b].imagePath,
              branch: b);
        }
      } else {
        await add(d.response.text.text.trim(), d.response.imagePath);
      }
      pageNo++;
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    if (failed.isNotEmpty) {
      AppSnackbar.warning(
          context.trRead('upload.err_pages_failed').replaceAll('{pages}', failed.join(', ')),
          context: context);
    } else {
      AppSnackbar.success(context.trRead('upload.saved_interactive'), context: context);
    }
    Navigator.of(context).pop();
  }

  Widget _buildInteractiveWriteForm() {
    final numbers = _interactivePageNumbers();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GuideBanner(onTap: _startInteractiveGuide),
        const SizedBox(height: 14),
        ..._writeDetailsSection(),
        const SizedBox(height: 14),
        SoftCard(
          color: _Tint.language,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Label(context.tr('upload.story_language'),
                  icon: Icons.translate_rounded, color: _Tint.mint),
              const SizedBox(height: 8),
              _manualLanguagePicker(),
              const SizedBox(height: 10),
              Text(
                context.tr('upload.interactive_voice_note'),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Label(context.tr('upload.pages'),
            icon: Icons.menu_book_rounded, color: _Tint.lavender),
        const SizedBox(height: 8),
        for (int i = 0; i < _interactiveDrafts.length; i++) ...[
          KeyedSubtree(
            key: i == 0 ? _firstPageKey : null,
            child: _InteractivePageCard(
            key: ObjectKey(_interactiveDrafts[i]),
            draft: _interactiveDrafts[i],
            pageNumber: numbers[i],
            canRemove: _interactiveDrafts.length > 1,
            onChanged: () => setState(() {}),
            pickImage: _pickImage,
            onRemove: () => _removeInteractivePage(i),
          ),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
          onPressed: _addInteractivePage,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryBlueDark,
            side: const BorderSide(color: AppColors.cardBorder),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: Text(context.tr('content.add_page'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 14),
        _BgmCard(
          enabled: _writeBgmEnabled,
          selectedTrack: _writeBgmTrack,
          volume: _writeBgmVolume,
          autoAllowed: false,
          onToggle: (v) => setState(() {
            _writeBgmEnabled = v;
            if (!v) _writeBgmTrack = null;
          }),
          onPick: () async {
            final track = await BgmPickerSheet.show(context,
                initialTrack: _writeBgmTrack);
            if (track != null) setState(() => _writeBgmTrack = track);
          },
          onClear: () => setState(() => _writeBgmTrack = null),
          onVolumeChanged: (v) => setState(() => _writeBgmVolume = v),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: _saveStyle,
            onPressed: _submitting ? null : _submitInteractive,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.tr('upload.save_interactive'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final guide = _guide;
    return Stack(
      children: [
        _buildPage(context),
        if (guide != null)
          Positioned.fill(
            child: ListenableBuilder(
              listenable: guide,
              builder: (context, _) => GuideOverlay(controller: guide, tabRect: (_) => null),
            ),
          ),
      ],
    );
  }

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF1D2), Color(0xFFF3ECFF), Color(0xFFE9F3FF)],
            stops: [0, 0.45, 1],
          ),
        ),
        child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            const BackPill(),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFC83D), Color(0xFFF08A4B)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_stories_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: WholeWordsText(
                    context.tr('upload.title'),
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                // Tap Paige to see the guide again.
                Semantics(
                  button: true,
                  label: context.tr('guide.replay'),
                  child: Tooltip(
                    message: context.tr('guide.replay'),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _replayGuide,
                      child: const ExcludeSemantics(child: PaigeMascot(width: 64)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            KeyedSubtree(key: _formatKey, child: _FormatSlider(
              format: _format,
              onChanged: (f) {
                setState(() => _setFormat(f));
                _maybeShowInteractiveGuide();
              },
            )),
            const SizedBox(height: 12),
            KeyedSubtree(key: _modeKey, child: _ModeToggle(
              mode: _mode,
              onChanged: (m) {
                setState(() => _mode = m);
                _maybeShowInteractiveGuide();
              },
            )),
            const SizedBox(height: 16),
            if (_format == _BookFormat.interactive && _mode == _Mode.write)
              _buildInteractiveWriteForm()
            else if (_mode == _Mode.write)
              _buildWriteForm()
            else
              _buildAiForm(),
          ],
        ),
        ),
      ),
    );
  }

  // write form

  static final _saveStyle = FilledButton.styleFrom(
    backgroundColor: _Tint.mint,
    foregroundColor: Colors.white,
    disabledBackgroundColor: _Tint.mint.withValues(alpha: 0.5),
    padding: const EdgeInsets.symmetric(vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );

  // Easy is green, Medium yellow, Hard orange.
  static Color _difficultyColor(String d) => switch (d) {
        'Medium' => const Color(0xFFFDE08A),
        'Hard' => const Color(0xFFFFC09A),
        _ => const Color(0xFFB8E6C8),
      };

  // Title / topic / difficulty / tags card and the cover card (both formats).
  List<Widget> _writeDetailsSection() {
    return [
      SoftCard(
        color: _Tint.details,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Label(context.tr('upload.title_field'),
                icon: Icons.title_rounded, color: _Tint.blue),
            TextField(
                controller: _titleCtrl,
                decoration:
                    InputDecoration(hintText: context.tr('upload.title_hint'))),
            const SizedBox(height: 14),
            _Label(context.tr('upload.topic'),
                icon: Icons.lightbulb_rounded, color: _Tint.yellow),
            TextField(
                controller: _topicCtrl,
                decoration:
                    InputDecoration(hintText: context.tr('upload.topic_hint'))),
            const SizedBox(height: 14),
            _Label(context.tr('content.field_difficulty'),
                icon: Icons.speed_rounded, color: _Tint.peach),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['Easy', 'Medium', 'Hard'].map((d) {
                return SoftChip(
                  label: context.tr('content.difficulty_${d.toLowerCase()}'),
                  selectedColor: _difficultyColor(d),
                  selected: _difficulty == d,
                  onTap: () => setState(() => _difficulty = d),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            _Label(context.tr('upload.tags'),
                icon: Icons.sell_rounded, color: _Tint.mint),
            TextField(
                controller: _tagsCtrl,
                decoration: InputDecoration(
                    hintText: context.tr('upload.tags_hint'))),
          ],
        ),
      ),
      const SizedBox(height: 14),
      // Cover image.
      SoftCard(
        color: _Tint.cover,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Label(context.tr('upload.cover_image'),
                icon: Icons.image_rounded, color: _Tint.pink),
            const SizedBox(height: 8),
            _ImagePickerBox(
              imagePath: _coverPath,
              height: 150,
              hint: context.tr('upload.cover_hint'),
              onPick: () => _pickImage((p) => _coverPath = p),
              onClear: _coverPath == null
                  ? null
                  : () => setState(() => _coverPath = null),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _manualLanguagePicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AppStrings.supportedCodes.map((code) {
        final active =
            (_manualLanguage ?? context.watch<LanguageState>().code) == code;
        return SoftChip(
          label: AppStrings.languageNames[code] ?? code,
          selected: active,
          selectedColor: AppColors.softMint,
          onTap: () => setState(() => _manualLanguage = code),
        );
      }).toList(),
    );
  }

  Widget _buildWriteForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._writeDetailsSection(),
        const SizedBox(height: 14),
        SoftCard(
          color: _Tint.language,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Label(context.tr('upload.story_language'),
                  icon: Icons.translate_rounded, color: _Tint.mint),
              const SizedBox(height: 8),
              _manualLanguagePicker(),
              const SizedBox(height: 16),
              _Label(context.tr('upload.book_audio'),
                  icon: Icons.headphones_rounded, color: _Tint.blue),
              const SizedBox(height: 6),
              Text(
                context.tr('upload.book_audio_hint'),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 10),
              _AudioPickerRow(
                audioPath: _audioPath,
                onPick: _pickAudio,
                onClear: _audioPath == null
                    ? null
                    : () => setState(() {
                          _audioPath = null;
                          for (final d in _pageDrafts) {
                            d.audioStartMs = null;
                          }
                        }),
                pickLabel: context.tr('upload.choose_audio'),
                replaceLabel: context.tr('upload.replace_audio'),
                clearLabel: context.tr('upload.clear'),
              ),
              // Page-marks editor: only shows with audio picked and 2+ pages.
              if (_audioPath != null && _pageDrafts.length > 1) ...[
                const SizedBox(height: 14),
                _PageBoundariesEditor(
                  audioPath: _audioPath!,
                  pageDrafts: _pageDrafts,
                  onChanged: () => setState(() {}),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Per-page builder.
        _Label(context.tr('upload.pages'),
            icon: Icons.menu_book_rounded, color: _Tint.lavender),
        const SizedBox(height: 8),
        for (int i = 0; i < _pageDrafts.length; i++) ...[
          _PageEditorCard(
            index: i,
            draft: _pageDrafts[i],
            canRemove: _pageDrafts.length > 1,
            onPickImage: () =>
                _pickImage((p) => _pageDrafts[i].imagePath = p),
            onClearImage: () =>
                setState(() => _pageDrafts[i].imagePath = null),
            onRemove: () => _removePage(i),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
          onPressed: _addPage,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryBlueDark,
            side: const BorderSide(color: AppColors.cardBorder),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: Text(context.tr('content.add_page'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 14),
        _BgmCard(
          enabled: _writeBgmEnabled,
          selectedTrack: _writeBgmTrack,
          volume: _writeBgmVolume,
          autoAllowed: false,
          onToggle: (v) => setState(() {
            _writeBgmEnabled = v;
            if (!v) _writeBgmTrack = null;
          }),
          onPick: () async {
            final track = await BgmPickerSheet.show(context,
                initialTrack: _writeBgmTrack);
            if (track != null) setState(() => _writeBgmTrack = track);
          },
          onClear: () => setState(() => _writeBgmTrack = null),
          onVolumeChanged: (v) => setState(() => _writeBgmVolume = v),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: _saveStyle,
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.tr('upload.save_storybook'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          context.tr('upload.pages_note'),
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  // AI form

  Widget _buildAiForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          color: _Tint.ai,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: AppColors.iconCirclePurple,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome,
                        size: 18, color: AppColors.primaryBlueDark),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.tr('upload.ai_heading'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Label(context.tr('upload.ai_topic'),
                  icon: Icons.lightbulb_rounded, color: _Tint.yellow),
              TextField(
                controller: _aiTopicCtrl,
                decoration: InputDecoration(
                  hintText: context.tr('upload.ai_topic_hint'),
                ),
              ),
              const SizedBox(height: 14),
              _Label(context.tr('content.field_difficulty'),
                  icon: Icons.speed_rounded, color: _Tint.peach),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Easy', 'Medium', 'Hard'].map((d) {
                  return SoftChip(
                    label: context.tr('content.difficulty_${d.toLowerCase()}'),
                    selectedColor: _difficultyColor(d),
                    selected: _aiDifficulty == d,
                    onTap: () => setState(() => _aiDifficulty = d),
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              // Matches the backend's sentencesPerPage().
              Text(
                context.tr(switch (_aiDifficulty) {
                  'Medium' => 'content.difficulty_hint_medium',
                  'Hard' => 'content.difficulty_hint_hard',
                  _ => 'content.difficulty_hint_easy',
                }),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),
              _Label(context.tr('upload.ai_length'),
                  icon: Icons.menu_book_rounded, color: _Tint.lavender),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                // Interactive books need a fixed length for the 1-in-4 cap.
                children: (_format == _BookFormat.interactive
                        ? _interactivePageOptions
                        : _pageOptions)
                    .map((p) {
                  return SoftChip(
                    label: p == 'Auto' ? context.tr('upload.ai_page_count_auto') : p,
                    selected: _aiPages == p,
                    selectedColor: AppColors.softMint,
                    onTap: () => setState(() => _setAiPages(p)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr(_format == _BookFormat.interactive
                    ? 'upload.ai_length_hint_interactive'
                    : 'upload.ai_length_hint'),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),
              _Label(context.tr('upload.ai_language'),
                  icon: Icons.translate_rounded, color: _Tint.mint),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppStrings.supportedCodes.map((code) {
                  final active = (_aiLanguage ??
                          context.watch<LanguageState>().code) ==
                      code;
                  return SoftChip(
                    label: AppStrings.languageNames[code] ?? code,
                    selected: active,
                    selectedColor: AppColors.softMint,
                    onTap: () => setState(() => _aiLanguage = code),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        if (_format == _BookFormat.interactive) ...[
          const SizedBox(height: 14),
          _InteractionSettingsCard(
            pageCount: int.tryParse(_aiPages) ?? 8,
            interactions: _aiInteractions,
            splits: _aiSplits,
            onInteractionsChanged: (v) => setState(() {
              _aiInteractions = v;
              if (_aiSplits > v) _aiSplits = v;
            }),
            onSplitsChanged: (v) => setState(() => _aiSplits = v),
            onShowGuide: _startInteractiveGuide,
          ),
        ],
        const SizedBox(height: 14),
        SoftCard(
          color: _Tint.cover,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Label(context.tr('upload.base_text'),
                  icon: Icons.notes_rounded, color: _Tint.pink),
              TextField(
                controller: _aiBaseTextCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: context.tr('upload.base_text_hint'),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _aiGenerateImage,
                activeThumbColor: AppColors.primaryBlueDark,
                onChanged: (v) => setState(() => _aiGenerateImage = v),
                secondary: const Icon(Icons.image_rounded, color: AppColors.primaryBlueDark),
                title: Text(context.tr('upload.gen_cover'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _BgmCard(
          enabled: _aiBgmEnabled,
          selectedTrack: _aiBgmTrack,
          volume: _aiBgmVolume,
          autoAllowed: true,
          onToggle: (v) => setState(() {
            _aiBgmEnabled = v;
            if (!v) _aiBgmTrack = null;
          }),
          onPick: () async {
            final track =
                await BgmPickerSheet.show(context, initialTrack: _aiBgmTrack);
            if (track != null) setState(() => _aiBgmTrack = track);
          },
          onClear: () => setState(() => _aiBgmTrack = null),
          onVolumeChanged: (v) => setState(() => _aiBgmVolume = v),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _Tint.lavender,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _generating ? null : _generateAi,
            icon: _generating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.auto_awesome, size: 20),
            label: Text(
              context.tr(_generating ? 'upload.generating' : 'upload.generate_ai'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ),
        if (_generating) ...[
          const SizedBox(height: 14),
          const _PendingCard(),
        ],
      ],
    );
  }
}

/* Shown while the AI writes the story and draws the pictures, so the
   caregiver knows it's working and not stuck. */
class _PendingCard extends StatelessWidget {
  const _PendingCard();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('upload.creating'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('upload.pending_body'),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              context.tr('upload.pending_wait'),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/* A tappable box showing the picked image, or an "add image" prompt when
   empty. */
class _ImagePickerBox extends StatelessWidget {
  final String? imagePath;
  final double height;
  final String hint;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const _ImagePickerBox({
    required this.imagePath,
    required this.height,
    required this.hint,
    required this.onPick,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.isNotEmpty;
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: hasImage
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(imagePath!), fit: BoxFit.cover),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Row(
                      children: [
                        _miniBtn(Icons.edit_rounded, onPick),
                        if (onClear != null) ...[
                          const SizedBox(width: 6),
                          _miniBtn(Icons.close_rounded, onClear!),
                        ],
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_photo_alternate_outlined,
                      size: 30, color: AppColors.textMuted),
                  const SizedBox(height: 6),
                  Text(hint,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
      ),
    );
  }

  Widget _miniBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}

/* One page row in the builder: page number, remove button, text field, and
   an image picker. */
class _PageEditorCard extends StatelessWidget {
  final int index;
  final _PageDraft draft;
  final bool canRemove;
  final VoidCallback onPickImage;
  final VoidCallback onClearImage;
  final VoidCallback onRemove;

  const _PageEditorCard({
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onPickImage,
    required this.onClearImage,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: _Tint.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.softMint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(context.tr('content.page_number').replaceAll('{n}', '${index + 1}'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              const Spacer(),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.textSecondary),
                  tooltip: context.tr('upload.remove_page'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: draft.text,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: context.tr('upload.page_text_hint'),
            ),
          ),
          const SizedBox(height: 10),
          _ImagePickerBox(
            imagePath: draft.imagePath,
            height: 130,
            hint: context.tr('upload.page_picture_hint'),
            onPick: onPickImage,
            onClear: draft.imagePath == null ? null : onClearImage,
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          _segment(context.tr('upload.mode_write'), Icons.edit_outlined, _Mode.write),
          _segment(context.tr('upload.generate_ai'), Icons.auto_awesome, _Mode.ai),
        ],
      ),
    );
  }

  Widget _segment(String label, IconData icon, _Mode value) {
    final selected = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: value == _Mode.write
                        ? const [Color(0xFFFFE08A), Color(0xFFFFC96B)]
                        : const [Color(0xFFD9C8FF), Color(0xFFB9A2F5)],
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: AppColors.textPrimary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* Player + per-page mark UI. The caregiver plays the recording and taps to
   mark where each page begins. The marks land on [_PageDraft.audioStartMs]
   so the child's player flips pages at exactly those points. */
class _PageBoundariesEditor extends StatefulWidget {
  final String audioPath;
  final List<_PageDraft> pageDrafts;
  final VoidCallback onChanged;
  const _PageBoundariesEditor({
    required this.audioPath,
    required this.pageDrafts,
    required this.onChanged,
  });

  @override
  State<_PageBoundariesEditor> createState() => _PageBoundariesEditorState();
}

class _PageBoundariesEditorState extends State<_PageBoundariesEditor> {
  late final AudioPlayer _player = AudioPlayer();
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _load();
    _posSub = _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durSub = _player.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _stateSub = _player.playerStateStream.listen((s) {
      if (!mounted) return;
      // `playing` stays true after the clip ends; check the processing
      // state so Play/Pause flips back correctly.
      final isPlaying =
          s.playing && s.processingState != ProcessingState.completed;
      if (isPlaying != _playing) setState(() => _playing = isPlaying);
    });
  }

  @override
  void didUpdateWidget(covariant _PageBoundariesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioPath != widget.audioPath) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final d = await _player.setFilePath(widget.audioPath);
      if (mounted) setState(() => _duration = d);
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(
            context.trRead('upload.could_not_load_audio'),
            context: context);
      }
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
    } else {
      // If we're at the end, rewind so the next Play starts from the top.
      final total = _duration;
      if (total != null && _position >= total) {
        await _player.seek(Duration.zero);
      }
      // Don't await play(): it finishes when playback ends, not starts.
      unawaited(_player.play());
    }
  }

  /* Mark the current spot as the start of page [index]. Page 0 is always 0
     and can't be changed. */
  void _markPage(int index) {
    if (index <= 0) return;
    final prev = _previousMarkMs(index);
    if (_position.inMilliseconds < prev) {
      AppSnackbar.warning(
        context.trRead('upload.mark_warning_backward'),
        context: context,
      );
      return;
    }
    widget.pageDrafts[index].audioStartMs = _position.inMilliseconds;
    widget.onChanged();
    setState(() {});
  }

  void _clearMark(int index) {
    widget.pageDrafts[index].audioStartMs = null;
    widget.onChanged();
    setState(() {});
  }

  // The last mark before [index] (0 if none).
  int _previousMarkMs(int index) {
    for (var i = index - 1; i > 0; i--) {
      final m = widget.pageDrafts[i].audioStartMs;
      if (m != null) return m;
    }
    return 0;
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes;
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration ?? Duration.zero;
    final maxMs = total.inMilliseconds.toDouble();
    final posMs = _position.inMilliseconds
        .toDouble()
        .clamp(0.0, maxMs == 0 ? 0.0 : maxMs);
    final pageLabel = context.tr('upload.page_label');
    final autoLabel = context.tr('upload.page_one_auto');
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(context.tr('upload.page_boundaries')),
          const SizedBox(height: 4),
          Text(
            context.tr('upload.page_boundaries_hint'),
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton.filled(
                onPressed: _duration == null ? null : _togglePlay,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primaryBlueDark,
                  foregroundColor: Colors.white,
                ),
                icon: Icon(_playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${_fmt(_position)} / ${_fmt(total)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primaryBlueDark,
              thumbColor: AppColors.primaryBlueDark,
              inactiveTrackColor: AppColors.cardBorder,
            ),
            child: Slider(
              value: posMs,
              min: 0,
              max: maxMs == 0 ? 1 : maxMs,
              onChanged: _duration == null
                  ? null
                  : (v) => _player.seek(Duration(milliseconds: v.round())),
            ),
          ),
          const Divider(height: 16),
          for (var i = 0; i < widget.pageDrafts.length; i++) ...[
            _PageMarkRow(
              label: '$pageLabel ${i + 1}',
              isPageOne: i == 0,
              markedAt: i == 0
                  ? autoLabel
                  : (widget.pageDrafts[i].audioStartMs != null
                      ? _fmt(Duration(
                          milliseconds:
                              widget.pageDrafts[i].audioStartMs!))
                      : null),
              markLabel: context.tr('upload.mark_now'),
              remarkLabel: context.tr('upload.remark'),
              onMark: i == 0 || _duration == null
                  ? null
                  : () => _markPage(i),
              onClear:
                  (i == 0 || widget.pageDrafts[i].audioStartMs == null)
                      ? null
                      : () => _clearMark(i),
            ),
            if (i < widget.pageDrafts.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _PageMarkRow extends StatelessWidget {
  final String label;
  final bool isPageOne;
  final String? markedAt;
  final String markLabel;
  final String remarkLabel;
  final VoidCallback? onMark;
  final VoidCallback? onClear;
  const _PageMarkRow({
    required this.label,
    required this.isPageOne,
    required this.markedAt,
    required this.markLabel,
    required this.remarkLabel,
    required this.onMark,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final marked = markedAt != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: marked
                  ? AppColors.softMint.withValues(alpha: 0.5)
                  : AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (marked && !isPageOne)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.check_rounded,
                        size: 14, color: AppColors.success),
                  ),
                Text(
                  markedAt ?? '-',
                  style:
                      const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (!isPageOne) ...[
            if (marked)
              TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryBlueDark,
                ),
                child: Text(remarkLabel),
              ),
            if (!marked)
              FilledButton(
                onPressed: onMark,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlueDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(markLabel,
                    style:
                        const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        ],
      ),
    );
  }
}

class _AudioPickerRow extends StatelessWidget {
  final String? audioPath;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final String pickLabel;
  final String replaceLabel;
  final String clearLabel;
  const _AudioPickerRow({
    required this.audioPath,
    required this.onPick,
    required this.onClear,
    required this.pickLabel,
    required this.replaceLabel,
    required this.clearLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (audioPath == null) {
      return OutlinedButton.icon(
        onPressed: onPick,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryBlueDark,
          side: const BorderSide(color: AppColors.cardBorder),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.audiotrack_rounded, size: 20),
        label: Text(pickLabel,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      );
    }
    // Show just the file name (full paths look messy on Android).
    final name = audioPath!.split(RegExp(r'[\\/]')).last;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.softPeach.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      // On a narrow screen the buttons drop under the file name.
      child: AdaptiveRow(
        gap: 10,
        trailingGap: 0,
        runGap: 4,
        minBodyWidth: 120,
        leading: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: AppColors.iconCircleBlue,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.audiotrack_rounded, size: 18),
        ),
        body: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: onPick,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryBlueDark,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(replaceLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                tooltip: clearLabel,
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color color;
  const _Label(this.text, {this.icon, this.color = AppColors.primaryBlueDark});

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: icon == null
          ? label
          : Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Icon(icon, size: 15, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(child: label),
              ],
            ),
    );
  }
}

/* Music card used in both Write and AI modes. When [autoAllowed] is true
   (AI mode) it shows an "Auto-select" hint instead of making the caregiver
   pick a track. */
class _BgmCard extends StatelessWidget {
  final bool enabled;
  final MusicTrack? selectedTrack;
  final int volume;
  final bool autoAllowed;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final ValueChanged<int> onVolumeChanged;

  const _BgmCard({
    required this.enabled,
    required this.selectedTrack,
    required this.volume,
    required this.autoAllowed,
    required this.onToggle,
    required this.onPick,
    required this.onClear,
    required this.onVolumeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: _Tint.music,
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            activeThumbColor: AppColors.primaryBlueDark,
            onChanged: onToggle,
            title: Text(context.tr('upload.bgm'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              context.tr(autoAllowed ? 'upload.bgm_auto_hint' : 'upload.bgm_hint'),
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          if (enabled) ...[
            const SizedBox(height: 6),
            if (selectedTrack != null) ...[
              _SelectedTrackRow(
                track: selectedTrack!,
                onChangeTap: onPick,
                onClear: onClear,
              ),
            ] else ...[
              OutlinedButton.icon(
                onPressed: onPick,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryBlueDark,
                  side: const BorderSide(color: AppColors.cardBorder),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.library_music_rounded, size: 18),
                label: Text(
                  context.tr(autoAllowed ? 'upload.choose_track_optional' : 'upload.choose_track'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (autoAllowed) ...[
                const SizedBox(height: 6),
                Text(
                  context.tr('upload.bgm_leave_empty'),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.volume_up_rounded,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(context.tr('upload.volume'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const Spacer(),
                Text('$volume%',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.primaryBlueDark,
                thumbColor: AppColors.primaryBlueDark,
                overlayColor:
                    AppColors.primaryBlue.withValues(alpha: 0.2),
                inactiveTrackColor: AppColors.cardBorder,
                trackHeight: 3,
              ),
              // Capped at the music ceiling (FR10, NFR5).
              child: Slider(
                value: AudioSafety.clampBgm(volume).toDouble(),
                min: 0,
                max: AudioSafety.bgmCeiling.toDouble(),
                divisions: AudioSafety.bgmCeiling ~/ 5,
                onChanged: (v) => onVolumeChanged(v.round()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectedTrackRow extends StatelessWidget {
  final MusicTrack track;
  final VoidCallback onChangeTap;
  final VoidCallback onClear;

  const _SelectedTrackRow({
    required this.track,
    required this.onChangeTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.iconCircleBlue,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.music_note_rounded,
              size: 20, color: AppColors.primaryBlueDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                if (track.composer != null && track.composer!.isNotEmpty)
                  Text(track.composer!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onChangeTap,
            child: Text(context.tr('upload.change'),
                style: const TextStyle(
                    color: AppColors.primaryBlueDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
