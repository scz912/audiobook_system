import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/music_track.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';

/* Bottom sheet to browse and pick a background-music track. Returns the
   chosen [MusicTrack], or null if closed without picking. */
class BgmPickerSheet extends StatefulWidget {
  final MusicTrack? initialTrack;

  const BgmPickerSheet({super.key, this.initialTrack});

  static Future<MusicTrack?> show(
    BuildContext context, {
    MusicTrack? initialTrack,
  }) {
    return showModalBottomSheet<MusicTrack>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => BgmPickerSheet(initialTrack: initialTrack),
    );
  }

  @override
  State<BgmPickerSheet> createState() => _BgmPickerSheetState();
}

class _BgmPickerSheetState extends State<BgmPickerSheet> {
  // Formats the server accepts. mp3 is kept as-is, the rest are converted.
  static const _uploadExtensions = [
    'mp3', 'mp4', 'm4a', 'aac', 'wav', 'ogg', 'flac', 'webm',
  ];
  // Matches the server's limit (and PHP's default upload_max_filesize on XAMPP).
  static const _maxUploadBytes = 40 * 1024 * 1024;

  final _searchCtrl = TextEditingController();
  final _previewPlayer = AudioPlayer();
  Timer? _debounce;

  List<String> _allTags = [];
  List<String> _compatibleTags = [];
  List<String> _selectedTags = [];
  List<MusicTrack> _tracks = [];
  MusicTrack? _pickedTrack;
  String? _playingTrackId; // trackId currently being previewed
  bool _previewLoading = false;
  bool _loadingTags = true;
  bool _loadingTracks = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _pickedTrack = widget.initialTrack;
    _searchCtrl.addListener(_onSearchChanged);
    _loadTags();
    _loadTracks();
    // Auto-stop preview when the track finishes.
    _previewPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && mounted) {
        setState(() => _playingTrackId = null);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePreview(MusicTrack track) async {
    if (_playingTrackId == track.trackId) {
      // Tap again → stop.
      await _previewPlayer.stop();
      setState(() => _playingTrackId = null);
      return;
    }
    // Switch to a different track.
    await _previewPlayer.stop();
    setState(() {
      _playingTrackId = track.trackId;
      _previewLoading = true;
    });
    try {
      await _previewPlayer.setUrl(track.fileUrl);
      await _previewPlayer.setVolume(0.8);
      await _previewPlayer.seek(Duration.zero);
      await _previewPlayer.play();
    } catch (_) {
      if (mounted) setState(() => _playingTrackId = null);
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  Future<void> _loadTags() async {
    final resp = await DatabaseService.getMusicTrackTags();
    if (!mounted) return;
    if (resp.success && resp.data is List) {
      setState(() {
        _allTags = (resp.data as List).map((t) => t.toString()).toList();
        _compatibleTags = List.from(_allTags);
        _loadingTags = false;
      });
    } else {
      setState(() => _loadingTags = false);
    }
  }

  Future<void> _loadTracks() async {
    setState(() => _loadingTracks = true);
    final resp = await DatabaseService.listMusicTracks(
      tags: _selectedTags.isEmpty ? null : _selectedTags,
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _tracks = resp.success && resp.data is List
          ? (resp.data as List).whereType<MusicTrack>().toList()
          : [];
      _loadingTracks = false;
    });
  }

  Future<void> _onTagToggled(String tag) async {
    final newSelected = List<String>.from(_selectedTags);
    if (newSelected.contains(tag)) {
      newSelected.remove(tag);
    } else {
      newSelected.add(tag);
    }
    setState(() => _selectedTags = newSelected);

    if (newSelected.isEmpty) {
      setState(() => _compatibleTags = List.from(_allTags));
    } else {
      final resp = await DatabaseService.getCompatibleMusicTags(newSelected);
      if (mounted && resp.success && resp.data is List) {
        setState(() =>
            _compatibleTags = (resp.data as List).map((t) => t.toString()).toList());
      }
    }
    await _loadTracks();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _loadTracks);
  }

  /* Pick a music file, upload it, and let the AI tag it. The new track is
     selected and its AI tags are shown so the caregiver can check them. */
  Future<void> _uploadMusic() async {
    if (!await _confirmCopyrightNotice() || !mounted) return;

    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _uploadExtensions,
        allowMultiple: false,
        withData: false,
      );
    } catch (e) {
      await _showMessage('Could not open files', '$e');
      return;
    }
    final file = result?.files.single;
    final path = file?.path;
    if (file == null || path == null) return;

    // Some pickers ignore the extension filter, so check again here.
    final ext = (file.extension ?? '').toLowerCase();
    if (!_uploadExtensions.contains(ext)) {
      await _showMessage('Unsupported file',
          'This file type can\'t be used. Please upload your music as an MP3 file.');
      return;
    }
    if (file.size > _maxUploadBytes) {
      await _showMessage('File too large',
          'Please choose a music file smaller than 40 MB.');
      return;
    }

    if (!mounted) return;
    final details = await _UploadDetailsDialog.show(
      context,
      suggestedTitle: _titleFromFilename(file.name),
    );
    if (details == null || !mounted) return;

    await _previewPlayer.stop();
    setState(() {
      _uploading = true;
      _playingTrackId = null;
    });

    final resp = await DatabaseService.uploadMusicTrack(
      filePath: path,
      title: details.title,
      composer: details.composer,
      durationSecs: await _measureDuration(path),
    );
    if (!mounted) return;
    setState(() => _uploading = false);

    if (!resp.success || resp.data is! MusicTrack) {
      await _showMessage(
        'Couldn\'t add music',
        resp.message.isNotEmpty ? resp.message : 'Please try again.',
      );
      return;
    }

    // Show the new track: clear filters so it's in the list, and pick it.
    final track = resp.data as MusicTrack;
    _searchCtrl.clear();
    _debounce?.cancel();
    setState(() {
      _pickedTrack = track;
      _selectedTags = [];
    });
    await Future.wait([_loadTags(), _loadTracks()]);
    if (mounted) await _UploadResultDialog.show(context, track);
  }

  /* Copyright reminder shown before every upload. Returns true only when
     the caregiver taps "I understand". */
  Future<bool> _confirmCopyrightNotice() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.copyright_rounded,
            color: AppColors.warning, size: 32),
        title: const Text('Copyright notice'),
        content: const Text(
          'If the music you upload is subject to copyright issues, we as '
          'developers will take down the music. Please make sure the music '
          'you use is free from copyright issues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlueDark),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /* Length of a local file in seconds, or null if it can't be read. Only a
     fallback - the server measures it itself when ffmpeg is installed. */
  Future<int?> _measureDuration(String path) async {
    final probe = AudioPlayer();
    try {
      final d = await probe
          .setFilePath(path)
          .timeout(const Duration(seconds: 5));
      return d?.inSeconds;
    } catch (_) {
      return null;
    } finally {
      unawaited(probe.dispose());
    }
  }

  // "happy-kids_music.mp3" → "Happy Kids Music"
  String _titleFromFilename(String name) {
    final dot = name.lastIndexOf('.');
    final base = (dot > 0 ? name.substring(0, dot) : name)
        .replaceAll(RegExp(r'[\s_\-]+'), ' ')
        .trim();
    return base
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  // Dialogs (not snackbars) so the message shows above this sheet.
  Future<void> _showMessage(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return Container(
      height: screenH * 0.62,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Choose Background Music',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: _uploading ? null : _uploadMusic,
                  icon: const Icon(Icons.upload_rounded, size: 20),
                  label: const Text('Upload'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryBlueDark,
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search title or composer',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: AppColors.primaryBlueDark, width: 1.5),
                ),
              ),
            ),
          ),
          if (!_loadingTags && _allTags.isNotEmpty)
            _TagFilterWrap(
              allTags: _allTags,
              compatibleTags:
                  _selectedTags.isEmpty ? _allTags : _compatibleTags,
              selectedTags: _selectedTags,
              onToggle: _onTagToggled,
            ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          Expanded(
            child: _uploading
                ? const _UploadingView()
                : _loadingTracks
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2))
                : _tracks.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No tracks found.\nTry clearing some filters.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _tracks.length,
                        separatorBuilder: (_, _) => const Divider(
                            height: 1, indent: 72, endIndent: 20),
                        itemBuilder: (_, i) {
                          final t = _tracks[i];
                          return _TrackTile(
                            track: t,
                            selected: _pickedTrack?.trackId == t.trackId,
                            isPlaying: _playingTrackId == t.trackId,
                            isPreviewLoading: _previewLoading &&
                                _playingTrackId == t.trackId,
                            onTap: () => setState(() => _pickedTrack = t),
                            onPlayTap: () => _togglePreview(t),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlueDark,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.cardBorder,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _pickedTrack == null || _uploading
                    ? null
                    : () => Navigator.of(context).pop(_pickedTrack),
                child: Text(
                  _pickedTrack == null
                      ? 'Select a track'
                      : 'Use "${_pickedTrack!.title}"',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* Chip row that hides tags which wouldn't match the current selection. */
class _TagFilterWrap extends StatelessWidget {
  final List<String> allTags;
  final List<String> compatibleTags;
  final List<String> selectedTags;
  final Future<void> Function(String) onToggle;

  const _TagFilterWrap({
    required this.allTags,
    required this.compatibleTags,
    required this.selectedTags,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // Keep the picked tags shown even if the server omits them - they're
    // what's doing the filtering.
    final visible = allTags
        .where((t) => selectedTags.contains(t) || compatibleTags.contains(t))
        .toList();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 102),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: visible.map((tag) {
              final selected = selectedTags.contains(tag);
              return GestureDetector(
                onTap: () => onToggle(tag),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primaryBlueDark
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? AppColors.primaryBlueDark
                          : AppColors.cardBorder,
                    ),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final MusicTrack track;
  final bool selected;
  final bool isPlaying;
  final bool isPreviewLoading;
  final VoidCallback onTap;
  final VoidCallback onPlayTap;

  const _TrackTile({
    required this.track,
    required this.selected,
    required this.isPlaying,
    required this.isPreviewLoading,
    required this.onTap,
    required this.onPlayTap,
  });

  String _fmt(int? secs) {
    if (secs == null) return '';
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primaryBlueDark
                    : AppColors.iconCircleBlue,
                shape: BoxShape.circle,
              ),
              child: Icon(
                selected
                    ? Icons.music_note_rounded
                    : Icons.music_note_outlined,
                size: 22,
                color:
                    selected ? Colors.white : AppColors.primaryBlueDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppColors.primaryBlueDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (track.composer != null &&
                      track.composer!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      track.composer!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary),
                    ),
                  ],
                  if (track.tags.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      track.tags.take(3).join(' · '),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                  if (track.isUserUploaded || track.sensoryNotes != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (track.isUserUploaded) ...[
                          const Icon(Icons.person_outline_rounded,
                              size: 13, color: AppColors.textSecondary),
                          const SizedBox(width: 3),
                          const Text(
                            'Your upload',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // AI flagged a sensory risk; tap to read it.
                        if (track.sensoryNotes != null)
                          Tooltip(
                            message: track.sensoryNotes!,
                            triggerMode: TooltipTriggerMode.tap,
                            child: const Icon(Icons.warning_amber_rounded,
                                size: 15, color: AppColors.warning),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (track.durationSecs != null)
              Text(
                _fmt(track.durationSecs),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            const SizedBox(width: 4),
            // Preview play/pause - does not pick the track.
            GestureDetector(
              onTap: onPlayTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: isPreviewLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primaryBlueDark),
                      )
                    : Icon(
                        isPlaying
                            ? Icons.pause_circle_rounded
                            : Icons.play_circle_rounded,
                        size: 32,
                        color: isPlaying
                            ? AppColors.primaryBlueDark
                            : AppColors.textMuted,
                      ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected
                  ? AppColors.primaryBlueDark
                  : AppColors.cardBorder,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

// Shown in place of the list while a file uploads and the AI listens to it.
class _UploadingView extends StatelessWidget {
  const _UploadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primaryBlueDark),
            SizedBox(height: 16),
            Text(
              'Uploading your music…',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'We convert it to MP3 if needed, then the AI listens to it\n'
              'and adds mood tags. This can take up to a minute.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/* Asks for the track's title (pre-filled from the file name) and an
   optional composer before uploading. Returns null if cancelled. */
class _UploadDetailsDialog extends StatefulWidget {
  final String suggestedTitle;

  const _UploadDetailsDialog({required this.suggestedTitle});

  static Future<({String title, String composer})?> show(
    BuildContext context, {
    required String suggestedTitle,
  }) {
    return showDialog<({String title, String composer})>(
      context: context,
      builder: (_) => _UploadDetailsDialog(suggestedTitle: suggestedTitle),
    );
  }

  @override
  State<_UploadDetailsDialog> createState() => _UploadDetailsDialogState();
}

class _UploadDetailsDialogState extends State<_UploadDetailsDialog> {
  late final _titleCtrl = TextEditingController(text: widget.suggestedTitle);
  final _composerCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _composerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add your music'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            maxLength: 200,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            controller: _composerCtrl,
            maxLength: 200,
            textCapitalization: TextCapitalization.words,
            decoration:
                const InputDecoration(labelText: 'Composer (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlueDark),
          onPressed: () => Navigator.of(context).pop((
            title: _titleCtrl.text.trim(),
            composer: _composerCtrl.text.trim(),
          )),
          child: const Text('Upload'),
        ),
      ],
    );
  }
}

/* Shows what the AI heard: its tags, a one-line summary, and any sensory
   caution, so the caregiver can decide whether the track suits their child. */
class _UploadResultDialog extends StatelessWidget {
  final MusicTrack track;

  const _UploadResultDialog({required this.track});

  static Future<void> show(BuildContext context, MusicTrack track) {
    return showDialog<void>(
      context: context,
      builder: (_) => _UploadResultDialog(track: track),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tagged = track.tags.isNotEmpty;
    return AlertDialog(
      title: Text('"${track.title}" added'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tagged) ...[
              const Text('AI tags',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in track.tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.iconCircleBlue,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(tag,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryBlueDark)),
                    ),
                  if (track.tempo != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Text('Tempo: ${track.tempo}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ] else
              const Text(
                'The AI couldn\'t tag this track right now. It\'s saved and '
                'you can still pick it, but it won\'t be chosen automatically '
                'for stories.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            if (track.aiSummary != null) ...[
              const SizedBox(height: 14),
              Text(track.aiSummary!),
            ],
            if (track.sensoryNotes != null) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 18, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(child: Text(track.sensoryNotes!)),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
