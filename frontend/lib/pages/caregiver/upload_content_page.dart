import 'dart:io';

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../i18n/app_strings.dart';
import '../../i18n/i18n.dart';
import '../../models/content_item.dart';
import '../../services/api_service.dart';
import '../../services/database_service.dart';
import '../../state/language_state.dart';
import '../../theme/app_colors.dart';
import '../../models/music_track.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/bgm_picker_sheet.dart';
import '../../widgets/soft_card.dart';
import '../../widgets/soft_chip.dart';

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

class UploadContentPage extends StatefulWidget {
  const UploadContentPage({super.key});

  @override
  State<UploadContentPage> createState() => _UploadContentPageState();
}

class _UploadContentPageState extends State<UploadContentPage> {
  _Mode _mode = _Mode.write;

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
  String _aiAge = '7-9';
  String _aiDifficulty = 'Easy';
  String _aiPages = 'Auto';
  bool _aiGenerateImage = true;
  bool _generating = false;
  // Language Gemini writes the story in. Defaults to the app language; the
  // caregiver can override it.
  String? _aiLanguage;

  static const _ages = ['5-6', '7-9', '8-11', '9-12'];
  static const _pageOptions = ['Auto', '4', '6', '8', '10', '12'];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _topicCtrl.dispose();
    _tagsCtrl.dispose();
    for (final p in _pageDrafts) {
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
        AppSnackbar.error('Could not pick image: $e', context: context);
      }
    }
  }

  Future<void> _pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
        withData: false,
      );
      final path = result?.files.single.path;
      if (path != null) {
        setState(() {
          _audioPath = path;
          // A new recording clears the old page marks — they no longer fit.
          for (final d in _pageDrafts) {
            d.audioStartMs = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error('Could not pick audio: $e', context: context);
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

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      AppSnackbar.warning('Title is required', context: context);
      return;
    }
    final hasContent = _pageDrafts.any((p) =>
        p.text.text.trim().isNotEmpty || p.imagePath != null);
    if (!hasContent) {
      AppSnackbar.warning('Add text or an image to at least one page',
          context: context);
      return;
    }
    if (_writeBgmEnabled && _writeBgmTrack == null) {
      AppSnackbar.warning(
          'Please choose a background music track, or disable BGM',
          context: context);
      return;
    }

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
      AppSnackbar.error('Created, but no audiobook id was returned',
          context: context);
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
        AppSnackbar.warning('Page $pageNo could not be saved: ${pageResp.message}',
            context: context);
      }
      pageNo++;
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    AppSnackbar.success('Storybook added to library', context: context);
    Navigator.of(context).pop();
  }

  // AI generate

  Future<void> _generateAi() async {
    final topic = _aiTopicCtrl.text.trim();
    if (topic.isEmpty) {
      AppSnackbar.warning('Please enter a topic or idea for the story',
          context: context);
      return;
    }
    setState(() => _generating = true);
    final language =
        _aiLanguage ?? context.read<LanguageState>().code; // app language by default
    final ApiResponse resp = await DatabaseService.generateAiContent(
      topic: topic,
      ageGroup: _aiAge,
      difficulty: _aiDifficulty,
      sourceText: _aiBaseTextCtrl.text.trim(),
      generateImage: _aiGenerateImage,
      pageCount: _aiPages == 'Auto' ? null : int.tryParse(_aiPages),
      includeBgm: _aiBgmEnabled,
      trackId: _aiBgmTrack?.trackId, // null = backend picks when music is on
      bgmVolume: _aiBgmVolume,
      language: language,
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
                        processing
                            ? 'Creating your storybook…'
                            : 'Created successfully!',
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
                  child: const Text('Done',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            const BackPill(),
            const SizedBox(height: 16),
            Text(
              context.tr('upload.title'),
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add a new story for your children',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            _ModeToggle(
              mode: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
            const SizedBox(height: 16),
            if (_mode == _Mode.write) _buildWriteForm() else _buildAiForm(),
          ],
        ),
      ),
    );
  }

  // write form

  Widget _buildWriteForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Label('Title'),
              TextField(
                  controller: _titleCtrl,
                  decoration:
                      const InputDecoration(hintText: 'e.g. The Gentle Dragon')),
              const SizedBox(height: 14),
              const _Label('Topic'),
              TextField(
                  controller: _topicCtrl,
                  decoration:
                      const InputDecoration(hintText: 'e.g. Fantasy, Animals')),
              const SizedBox(height: 14),
              const _Label('Difficulty'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Easy', 'Medium', 'Hard'].map((d) {
                  return SoftChip(
                    label: d,
                    selected: _difficulty == d,
                    onTap: () => setState(() => _difficulty = d),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              const _Label('Tags'),
              TextField(
                  controller: _tagsCtrl,
                  decoration: const InputDecoration(
                      hintText: 'comma, separated, tags')),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Cover image.
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Label('Cover image'),
              const SizedBox(height: 8),
              _ImagePickerBox(
                imagePath: _coverPath,
                height: 150,
                hint: 'Add a cover image',
                onPick: () => _pickImage((p) => _coverPath = p),
                onClear: _coverPath == null
                    ? null
                    : () => setState(() => _coverPath = null),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Label(context.tr('upload.story_language')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppStrings.supportedCodes.map((code) {
                  final active = (_manualLanguage ??
                          context.watch<LanguageState>().code) ==
                      code;
                  return SoftChip(
                    label: AppStrings.languageNames[code] ?? code,
                    selected: active,
                    selectedColor: AppColors.softMint,
                    onTap: () => setState(() => _manualLanguage = code),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              _Label(context.tr('upload.book_audio')),
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
        const _Label('Pages'),
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
          label: const Text('Add page',
              style: TextStyle(fontWeight: FontWeight.w700)),
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
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: AppColors.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Storybook',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Each page can have its own text and picture. The first image (or the '
          'cover) is used as the library thumbnail.',
          style: TextStyle(
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
                  const Expanded(
                    child: Text('Generate with Gemini AI',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Describe a topic and AI will write a calm, autism-friendly '
                'story for you to review.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              const _Label('Topic / idea'),
              TextField(
                controller: _aiTopicCtrl,
                decoration: const InputDecoration(
                  hintText: 'e.g. A shy turtle who makes a new friend',
                ),
              ),
              const SizedBox(height: 14),
              const _Label('Age range'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _ages.map((a) {
                  return SoftChip(
                    label: a,
                    selected: _aiAge == a,
                    selectedColor: AppColors.softMint,
                    onTap: () => setState(() => _aiAge = a),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              const _Label('Difficulty'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Easy', 'Medium', 'Hard'].map((d) {
                  return SoftChip(
                    label: d,
                    selected: _aiDifficulty == d,
                    onTap: () => setState(() => _aiDifficulty = d),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              const _Label('Story length (pages)'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _pageOptions.map((p) {
                  return SoftChip(
                    label: p,
                    selected: _aiPages == p,
                    selectedColor: AppColors.softMint,
                    onTap: () => setState(() => _aiPages = p),
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              const Text(
                '“Auto” picks a short length (4–6 pages). Each page is one AI '
                'picture (~10–15s), so fewer pages means a faster result.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),
              _Label(context.tr('upload.ai_language')),
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
        const SizedBox(height: 14),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Label('Base text (optional)'),
              TextField(
                controller: _aiBaseTextCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText:
                      'Paste existing text to rewrite into a gentle story, or leave empty.',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _aiGenerateImage,
                activeThumbColor: AppColors.primaryBlueDark,
                onChanged: (v) => setState(() => _aiGenerateImage = v),
                title: const Text('Generate a cover image',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                  'Uses Gemini image generation (may be skipped on the free tier).',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
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
              backgroundColor: AppColors.primaryBlueDark,
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
              _generating ? 'Generating…' : 'Generate with AI',
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
                  children: const [
                    Text(
                      'Creating your storybook…',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Writing the story and drawing each picture.',
                      style: TextStyle(
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
            child: const Text(
              'Each page gets its own AI picture (about 10–15s each), so this '
              'can take up to a minute. Please keep the app open.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
                child: Text('Page ${index + 1}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              const Spacer(),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.textSecondary),
                  tooltip: 'Remove page',
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: draft.text,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Text for this page…',
            ),
          ),
          const SizedBox(height: 10),
          _ImagePickerBox(
            imagePath: draft.imagePath,
            height: 130,
            hint: 'Add a picture for this page',
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
          _segment('Write', Icons.edit_outlined, _Mode.write),
          _segment('Generate with AI', Icons.auto_awesome, _Mode.ai),
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
            color: selected ? AppColors.primaryBlue : Colors.transparent,
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
                  markedAt ?? '—',
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
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.iconCircleBlue,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.audiotrack_rounded, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
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
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            activeThumbColor: AppColors.primaryBlueDark,
            onChanged: onToggle,
            title: const Text('Background Music',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              autoAllowed
                  ? 'AI will pick a fitting track, or choose one below.'
                  : 'Add gentle music behind the narration.',
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
                  autoAllowed ? 'Choose a track (optional)' : 'Choose a track',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (autoAllowed) ...[
                const SizedBox(height: 6),
                const Text(
                  'Leave empty to let AI pick the best match for the story.',
                  style: TextStyle(
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
                const Text('Volume',
                    style: TextStyle(
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
              child: Slider(
                value: volume.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
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
            child: const Text('Change',
                style: TextStyle(
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
