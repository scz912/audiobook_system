import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/music_track.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';

/* Bottom sheet that lets the caregiver browse and select a background music
   track. Returns the chosen [MusicTrack] via [Navigator.pop], or null if the
   sheet is dismissed without a selection. */
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
            child: _loadingTracks
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
                onPressed: _pickedTrack == null
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

/* Chip row that hides tags incompatible with the current selection.
   Max visible height is ~2.5 chip rows (non-scrollable; extra chips are
   clipped — the selection logic prevents reaching unreachable combinations). */
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
    // Keep selected tags even if they fall out of compatibleTags (they define
    // the current filter — removing the tag re-opens the set).
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
            // Preview play/pause button — tapping does NOT select the track.
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
