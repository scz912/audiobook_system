import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../audio/piano_synth.dart';
import '../../i18n/i18n.dart';
import '../../services/piano_export_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/guide.dart';
import 'piano_keyboard.dart';
import 'recording_player_view.dart';

enum _Mode { playing, recording, paused, preparing, listening }

// The page is drawn a quarter turn clockwise (the phone itself stays upright).
const _quarterTurns = 1;

const _recordRed = Color(0xFFE53950);
const _bodyTop = Color(0xFF454B85);
const _bodyBottom = Color(0xFF2C3060);

/* A small C major piano (do to do), shown as a tab in both the caregiver
   and child taskbars. The phone stays upright: the page is drawn turned a
   quarter clockwise, so it is played with the phone held sideways. The
   record button in the top bar captures the keys played; when the
   recording is stopped it can be listened to and saved as an MP3. */
class PianoPage extends StatefulWidget {
  const PianoPage({
    super.key,
    this.onGuideEvent,
    this.recordButtonKey,
    this.stopButtonKey,
    this.keyboardKey,
    this.saveButtonKey,
  });

  // Tells a running guide when a note is played, a recording starts or
  // stops, or one is saved.
  final ValueChanged<GuideEvent>? onGuideEvent;
  // So a guide can ring the record and stop buttons.
  final GlobalKey? recordButtonKey;
  final GlobalKey? stopButtonKey;
  // And the keys, and the save button once a recording is done.
  final GlobalKey? keyboardKey;
  final GlobalKey? saveButtonKey;

  @override
  State<PianoPage> createState() => PianoPageState();
}

class PianoPageState extends State<PianoPage> {
  // Snackbars and dialogs are shown inside the turned page, so they read
  // the same way round as the piano.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // One player per key, so different keys can ring together.
  final List<AudioPlayer> _keyPlayers = [];

  _Mode _mode = _Mode.playing;
  final Stopwatch _clock = Stopwatch();
  final List<PianoNoteEvent> _events = [];
  Timer? _ticker;

  PianoMix? _mix;
  String? _wavPath;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    /* The page is already drawn sideways for a phone held upright. If the
       phone's auto-rotate also turned the app, the piano would be turned
       twice, so keep the app upright while the piano is open. */
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final paths = await PianoSynth.prepareNoteFiles();
    for (final path in paths) {
      final player = AudioPlayer(handleAudioSessionActivation: false);
      await player.setFilePath(path);
      if (!mounted) {
        player.dispose();
        return;
      }
      _keyPlayers.add(player);
    }
  }

  @override
  void dispose() {
    // Back to the app's normal rotation for the other pages.
    SystemChrome.setPreferredOrientations([]);
    _ticker?.cancel();
    for (final p in _keyPlayers) {
      p.dispose();
    }
    super.dispose();
  }

  void _onKey(int key) {
    if (key < _keyPlayers.length) {
      final p = _keyPlayers[key];
      p.seek(Duration.zero);
      p.play();
    }
    if (_mode == _Mode.recording) _events.add(PianoNoteEvent(key, _clock.elapsed));
    widget.onGuideEvent?.call(GuideEvent.notePlayed);
  }

  // ---- Recording ----

  void _startRecording() {
    _events.clear();
    _clock
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => setState(() {}));
    setState(() => _mode = _Mode.recording);
    widget.onGuideEvent?.call(GuideEvent.recordingStarted);
  }

  void _togglePause() {
    setState(() {
      if (_mode == _Mode.recording) {
        _clock.stop();
        _mode = _Mode.paused;
      } else {
        _clock.start();
        _mode = _Mode.recording;
      }
    });
  }

  Future<void> _stopRecording() async {
    _clock.stop();
    _ticker?.cancel();
    if (_events.isEmpty) {
      setState(() => _mode = _Mode.playing);
      AppSnackbar.info(context.trRead('piano.nothing_recorded'), context: _snackContext);
      return;
    }
    setState(() => _mode = _Mode.preparing);

    final mix = await PianoSynth.mixRecording(List.of(_events), _clock.elapsed);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/piano_recording_${DateTime.now().millisecondsSinceEpoch}.wav');
    await file.writeAsBytes(PianoSynth.encodeWav(mix.pcm));
    if (!mounted) return;
    setState(() {
      _mix = mix;
      _wavPath = file.path;
      _saved = false;
      _mode = _Mode.listening;
    });
    widget.onGuideEvent?.call(GuideEvent.recordingStopped);
  }

  // ---- Listening ----

  Future<void> _closeListening() async {
    if (!_saved && !await _confirmDiscard()) return;
    final old = _wavPath;
    setState(() {
      _mix = null;
      _wavPath = null;
      _mode = _Mode.playing;
    });
    if (old != null) File(old).delete().ignore();
  }

  Future<void> _save() async {
    final mix = _mix;
    if (mix == null || _saving) return;

    if (!await PianoExportService.hasConsent()) {
      if (!mounted || !await _askSaveConsent()) return;
      await PianoExportService.giveConsent();
    }
    final access = await PianoExportService.requestStorageAccess();
    if (!mounted) return;
    if (access != StorageAccess.granted) {
      AppSnackbar.show(
        context.trRead('piano.permission_denied'),
        context: _snackContext,
        kind: AppSnackKind.warning,
        action: access == StorageAccess.permanentlyDenied
            ? SnackBarAction(
                label: context.trRead('piano.open_settings'),
                onPressed: PianoExportService.openSettings,
              )
            : null,
      );
      return;
    }

    final name = await _askName();
    if (name == null || !mounted) return;

    setState(() => _saving = true);
    try {
      final file = await PianoExportService.saveMp3(mix.pcm, name: name);
      if (!mounted) return;
      _saved = true;
      widget.onGuideEvent?.call(GuideEvent.recordingSaved);
      AppSnackbar.success(
        context
            .trRead(PianoExportService.savesToFilesApp
                ? 'piano.saved_to_files'
                : 'piano.saved_to')
            .replaceAll('{name}', file.uri.pathSegments.last),
        context: _snackContext,
      );
    } catch (_) {
      if (mounted) AppSnackbar.error(context.trRead('piano.save_failed'), context: _snackContext);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- Dialogs ----

  // Below the page's own messenger, so snackbars appear turned with it.
  BuildContext get _snackContext => _scaffoldKey.currentContext ?? context;

  Future<bool> _askSaveConsent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => RotatedBox(
        quarterTurns: _quarterTurns,
        child: _PianoDialog(
          icon: Icons.folder_rounded,
          iconColor: AppColors.success,
          title: ctx.tr('piano.permission_title'),
          body: ctx.tr(PianoExportService.savesToFilesApp
              ? 'piano.permission_body_files'
              : 'piano.permission_body'),
          cancel: ctx.tr('piano.permission_deny'),
          confirm: ctx.tr('piano.permission_allow'),
          confirmColor: AppColors.success,
        ),
      ),
    );
    return ok ?? false;
  }

  /* Asks what to call the recording. Null if cancelled; empty = a dated
     name. Shown upright, not turned like the piano: the phone's keyboard
     always opens upright, and a turned box squeezed above it breaks. */
  Future<String?> _askName() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => const _NameDialog(),
    );
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => RotatedBox(
        quarterTurns: _quarterTurns,
        child: _PianoDialog(
          icon: Icons.music_off_rounded,
          iconColor: AppColors.warning,
          title: ctx.tr('piano.discard_title'),
          body: ctx.tr('piano.discard_body'),
          cancel: ctx.tr('common.cancel'),
          confirm: ctx.tr('piano.discard'),
          confirmColor: AppColors.warning,
        ),
      ),
    );
    return ok ?? false;
  }

  // Anything that would be lost by leaving the page.
  bool get _hasUnsavedWork =>
      ((_mode == _Mode.recording || _mode == _Mode.paused) && _events.isNotEmpty) ||
      _mode == _Mode.preparing ||
      (_mode == _Mode.listening && !_saved);

  /* Called by the taskbar before switching away from the piano tab.
     Returns whether it's fine to go, asking first if a recording that
     hasn't been saved would be lost. */
  Future<bool> confirmLeave() async => !_hasUnsavedWork || await _confirmDiscard();

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    // Its own messenger and scaffold, inside the turn, so snackbars come
    // up along the piano's bottom edge the right way round.
    return RotatedBox(
      quarterTurns: _quarterTurns,
      child: ScaffoldMessenger(
        child: Scaffold(
          key: _scaffoldKey,
          // See-through, so the taskbar's dyed background shows; just a
          // soft white sheen on top of it.
          backgroundColor: Colors.transparent,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.45),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
            child: Stack(
              children: [
                const _FloatingNotesBackdrop(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    children: [
                      _buildTopBar(context),
                      const SizedBox(height: 10),
                      Expanded(child: _buildBody()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final listening = _mode == _Mode.listening;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          // The taskbar (or the system back gesture) leaves the page; the
          // only button here closes a recording to go back to the keys.
          if (listening) ...[
            _CircleButton(
              icon: Icons.close_rounded,
              tooltip: context.tr('piano.close'),
              onTap: _closeListening,
            ),
            const SizedBox(width: 12),
          ],
          _TitlePill(
            text: context.tr(listening ? 'piano.your_recording' : 'piano.title'),
            icon: listening ? Icons.graphic_eq_rounded : Icons.piano_rounded,
          ),
          const Spacer(),
          ..._buildRecordControls(context),
        ],
      ),
    );
  }

  List<Widget> _buildRecordControls(BuildContext context) {
    switch (_mode) {
      case _Mode.playing:
        return [
          _CircleButton(
            key: widget.recordButtonKey,
            tooltip: context.tr('piano.record'),
            onTap: _startRecording,
            size: 48,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(color: _recordRed, shape: BoxShape.circle),
            ),
          ),
        ];
      case _Mode.recording:
      case _Mode.paused:
        final recording = _mode == _Mode.recording;
        return [
          _RecordingTimer(elapsed: _clock.elapsed, live: recording),
          const SizedBox(width: 10),
          _CircleButton(
            icon: recording ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: context.tr(recording ? 'piano.pause' : 'piano.resume'),
            onTap: _togglePause,
            size: 48,
          ),
          const SizedBox(width: 10),
          _CircleButton(
            key: widget.stopButtonKey,
            tooltip: context.tr('piano.stop'),
            onTap: _stopRecording,
            size: 48,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(color: _recordRed, borderRadius: BorderRadius.circular(4)),
            ),
          ),
        ];
      case _Mode.preparing:
      case _Mode.listening:
        return const [];
    }
  }

  Widget _buildBody() {
    switch (_mode) {
      case _Mode.preparing:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF7E57C2)),
              const SizedBox(height: 14),
              Text(
                context.tr('piano.preparing'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        );
      case _Mode.listening:
        return RecordingPlayerView(
          key: ValueKey(_wavPath),
          wavPath: _wavPath!,
          peaks: _mix!.peaks,
          saving: _saving,
          onSave: _save,
          saveButtonKey: widget.saveButtonKey,
        );
      case _Mode.playing:
      case _Mode.recording:
      case _Mode.paused:
        return _PianoBody(
          key: widget.keyboardKey,
          recording: _mode == _Mode.recording,
          child: PianoKeyboard(onKeyDown: _onKey),
        );
    }
  }
}

/* The piano's case: a dark indigo frame, a felt strip and a rainbow
   trim, with the keys inside. Glows red while recording. */
class _PianoBody extends StatelessWidget {
  final bool recording;
  final Widget child;
  const _PianoBody({super.key, required this.recording, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bodyTop, _bodyBottom],
        ),
        boxShadow: [
          BoxShadow(
            color: recording
                ? _recordRed.withValues(alpha: 0.45)
                : _bodyBottom.withValues(alpha: 0.35),
            blurRadius: recording ? 26 : 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Rainbow trim along the top edge of the case.
          Container(
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
              gradient: LinearGradient(colors: pianoKeyColors),
            ),
          ),
          const SizedBox(height: 10),
          // Felt strip the keys sit under.
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFFC94A5F),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData? icon;
  final Widget? child;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  const _CircleButton({
    super.key,
    this.icon,
    this.child,
    required this.tooltip,
    required this.onTap,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(side: BorderSide(color: AppColors.cardBorder, width: 1.5)),
        elevation: 2,
        shadowColor: Colors.black26,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: child ?? Icon(icon, size: size * 0.5, color: AppColors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class _TitlePill extends StatelessWidget {
  final String text;
  final IconData icon;
  const _TitlePill({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFFEC407A), Color(0xFF7E57C2)]),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// Elapsed recording time with a red dot that pulses while recording.
class _RecordingTimer extends StatefulWidget {
  final Duration elapsed;
  final bool live;
  const _RecordingTimer({required this.elapsed, required this.live});

  @override
  State<_RecordingTimer> createState() => _RecordingTimerState();
}

class _RecordingTimerState extends State<_RecordingTimer> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.elapsed;
    String two(int v) => v.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _recordRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: widget.live
                ? _pulse.drive(Tween(begin: 0.3, end: 1))
                : const AlwaysStoppedAnimation(0.4),
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: _recordRed, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${two(e.inMinutes)}:${two(e.inSeconds % 60)}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _PianoDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String cancel;
  final String confirm;
  final Color confirmColor;

  const _PianoDialog({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.cancel,
    required this.confirm,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Landscape leaves little height, so let it scroll if needed.
      scrollable: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: CircleAvatar(
        radius: 24,
        backgroundColor: iconColor.withValues(alpha: 0.15),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            cancel,
            style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: Text(confirm, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

// "Give it a name?" before saving a recording.
class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.success.withValues(alpha: 0.15),
        child: const Icon(Icons.edit_rounded, color: AppColors.success),
      ),
      title: Text(
        context.tr('piano.name_title'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: TextField(
          controller: _name,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: context.tr('piano.name_hint'),
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            context.tr('common.cancel'),
            style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
          ),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_name.text.trim()),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          icon: const Icon(Icons.save_alt_rounded),
          label: Text(context.tr('piano.name_save'), style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

// Faint music notes scattered behind everything, for a playful feel.
class _FloatingNotesBackdrop extends StatelessWidget {
  const _FloatingNotesBackdrop();

  static const _notes = [
    (0.06, 0.20, Icons.music_note_rounded, 0xFFEC407A, 34.0, -0.2),
    (0.30, 0.08, Icons.queue_music_rounded, 0xFF7E57C2, 28.0, 0.15),
    (0.55, 0.14, Icons.music_note_rounded, 0xFF42A5F5, 30.0, 0.25),
    (0.78, 0.06, Icons.audiotrack_rounded, 0xFF5CB860, 32.0, -0.15),
    (0.92, 0.30, Icons.music_note_rounded, 0xFFFF9800, 26.0, 0.3),
    (0.02, 0.85, Icons.audiotrack_rounded, 0xFF26BCD0, 30.0, 0.2),
    (0.96, 0.88, Icons.queue_music_rounded, 0xFFEF5350, 28.0, -0.25),
  ];

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, box) {
            return Stack(
              children: [
                for (final (x, y, icon, color, size, angle) in _notes)
                  Positioned(
                    left: x * box.maxWidth - size / 2,
                    top: y * box.maxHeight - size / 2,
                    child: Transform.rotate(
                      angle: angle,
                      child: Icon(icon, size: size, color: Color(color).withValues(alpha: 0.18)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
