import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../i18n/i18n.dart';
import '../../theme/app_colors.dart';

const _waveStart = Color(0xFFEC407A);
const _waveEnd = Color(0xFF7E57C2);
const _waveIdle = Color(0xFFD9DCEB);

/* Listening to a finished recording, laid out like a phone's voice
   recorder: the time, the soundwave with a playhead, then the controls. */
class RecordingPlayerView extends StatefulWidget {
  final String wavPath;
  final Float32List peaks;
  final bool saving;
  final VoidCallback onSave;
  // So a guide can ring the save button.
  final GlobalKey? saveButtonKey;

  const RecordingPlayerView({
    super.key,
    required this.wavPath,
    required this.peaks,
    required this.saving,
    required this.onSave,
    this.saveButtonKey,
  });

  @override
  State<RecordingPlayerView> createState() => _RecordingPlayerViewState();
}

class _RecordingPlayerViewState extends State<RecordingPlayerView> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  // Where the finger is while dragging along the soundwave.
  double? _dragFraction;

  @override
  void initState() {
    super.initState();
    _subs.add(_player
        .createPositionStream(
          minPeriod: const Duration(milliseconds: 30),
          maxPeriod: const Duration(milliseconds: 30),
        )
        .listen((p) => setState(() => _position = p)));
    _subs.add(_player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        // Back to the start, ready to listen again.
        _player.pause();
        _player.seek(Duration.zero);
      }
      setState(() => _playing = s.playing && s.processingState != ProcessingState.completed);
    }));
    _load();
  }

  Future<void> _load() async {
    final d = await _player.setFilePath(widget.wavPath);
    if (!mounted) return;
    setState(() => _duration = d ?? Duration.zero);
    _player.play();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  void _togglePlay() => _playing ? _player.pause() : _player.play();

  void _skip(Duration by) {
    var to = _position + by;
    if (to < Duration.zero) to = Duration.zero;
    if (to > _duration) to = _duration;
    _player.seek(to);
  }

  void _stop() {
    _player.pause();
    _player.seek(Duration.zero);
  }

  void _seekToFraction(double f) {
    _player.seek(_duration * f.clamp(0.0, 1.0));
  }

  double get _fraction {
    if (_dragFraction != null) return _dragFraction!;
    final total = _duration.inMilliseconds;
    if (total == 0) return 0;
    return (_position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _dragFraction != null ? _duration * _dragFraction! : _position;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _waveEnd.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Time, above the soundwave.
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: _formatPrecise(shown),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              TextSpan(
                text: '  /  ${_format(_duration)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              double fractionAt(double dx) => (dx / box.maxWidth).clamp(0.0, 1.0);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _seekToFraction(fractionAt(d.localPosition.dx)),
                onHorizontalDragStart: (d) =>
                    setState(() => _dragFraction = fractionAt(d.localPosition.dx)),
                onHorizontalDragUpdate: (d) =>
                    setState(() => _dragFraction = fractionAt(d.localPosition.dx)),
                onHorizontalDragEnd: (_) {
                  _seekToFraction(_dragFraction ?? _fraction);
                  setState(() => _dragFraction = null);
                },
                child: CustomPaint(
                  size: Size(box.maxWidth, box.maxHeight),
                  painter: _WaveformPainter(peaks: widget.peaks, progress: _fraction),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          // Playback controls centred in the card, Save pinned to the right.
          // The empty Expanded on the left balances the Save side.
          Row(
            children: [
              const Expanded(child: SizedBox()),
              _RoundIcon(
                icon: Icons.replay_5_rounded,
                tooltip: context.tr('piano.back_5'),
                onTap: () => _skip(const Duration(seconds: -5)),
              ),
              const SizedBox(width: 18),
              _PlayButton(
                playing: _playing,
                tooltip: context.tr(_playing ? 'piano.pause' : 'piano.play'),
                onTap: _togglePlay,
              ),
              const SizedBox(width: 18),
              _RoundIcon(
                icon: Icons.forward_5_rounded,
                tooltip: context.tr('piano.forward_5'),
                onTap: () => _skip(const Duration(seconds: 5)),
              ),
              const SizedBox(width: 18),
              _RoundIcon(
                icon: Icons.stop_rounded,
                tooltip: context.tr('piano.stop'),
                onTap: _stop,
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  // Shrinks rather than overflows on narrow phones.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _SaveButton(key: widget.saveButtonKey, saving: widget.saving, onTap: widget.onSave),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _format(Duration d) =>
      '${_two(d.inMinutes)}:${_two(d.inSeconds % 60)}';

  static String _formatPrecise(Duration d) =>
      '${_format(d)}.${(d.inMilliseconds % 1000) ~/ 100}';
}

/* Bars mirrored around a centre line. Played bars are pink-to-purple, the
   rest grey, with a playhead at the current spot. */
class _WaveformPainter extends CustomPainter {
  final Float32List peaks;
  final double progress;
  _WaveformPainter({required this.peaks, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 4.0;
    const gap = 3.0;
    final count = (size.width / (barWidth + gap)).floor();
    if (count <= 0 || peaks.isEmpty) return;
    final mid = size.height / 2;
    final playedX = size.width * progress;

    final played = Paint()
      ..shader = const LinearGradient(colors: [_waveStart, _waveEnd])
          .createShader(Offset.zero & size);
    final idle = Paint()..color = _waveIdle;

    for (var i = 0; i < count; i++) {
      final peak = peaks[(i * peaks.length / count).floor()];
      final h = (peak * (size.height - 8)).clamp(4.0, size.height - 8);
      final x = i * (barWidth + gap) + gap / 2;
      final bar = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, mid - h / 2, barWidth, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(bar, x + barWidth / 2 <= playedX ? played : idle);
    }

    // Playhead.
    final head = Paint()..color = _waveStart;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(playedX - 1.25, 4, 2.5, size.height - 4),
        const Radius.circular(2),
      ),
      head,
    );
    canvas.drawCircle(Offset(playedX, 5), 5, head);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress || old.peaks != peaks;
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundIcon({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFFF2EEFB),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 50,
            height: 50,
            child: Icon(icon, size: 28, color: _waveEnd),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool playing;
  final String tooltip;
  final VoidCallback onTap;
  const _PlayButton({required this.playing, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_waveStart, _waveEnd],
            ),
            boxShadow: [
              BoxShadow(
                color: _waveStart.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 38,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final bool saving;
  final VoidCallback onTap;
  const _SaveButton({super.key, required this.saving, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: saving ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.success,
        disabledBackgroundColor: AppColors.success.withValues(alpha: 0.6),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
      icon: saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
            )
          : const Icon(Icons.download_rounded, size: 20),
      label: Text(context.tr(saving ? 'piano.saving' : 'piano.save_mp3')),
    );
  }
}
