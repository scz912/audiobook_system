import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_safety.dart';

class AudioEngine {
  AudioEngine._internal();
  static final AudioEngine instance = AudioEngine._internal();

  final AudioPlayer _player = AudioPlayer();
  late final AudioFader _fader = AudioFader(_player);
  bool _sessionConfigured = false;

  AudioPlayer get player => _player;

  Future<void> _ensureSession() async {
    if (_sessionConfigured) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    _sessionConfigured = true;
  }

  // Load a url and return the clip's length (if known).
  Future<Duration?> loadAudio(String url) async {
    await _ensureSession();
    return _player.setUrl(url);
  }

  /* Plain play, used for the page-to-page hand-off mid-story. A fade-out
     earlier may have left the volume at 0, so put it back first. */
  Future<void> play() {
    _fader.cancel();
    unawaited(_player.setVolume(1.0));
    return _player.play();
  }

  Future<void> pause() => _player.pause();

  /* Start (or resume) with a soft fade-in instead of jumping straight to
     full volume (NFR5). Doesn't wait for playback to end. */
  Future<void> fadeInPlay() => _fader.fadeInPlay(1.0);

  /// Fade out softly, then pause (NFR5).
  Future<void> fadeOutPause() => _fader.fadeOutPause();

  Future<void> stop() {
    _fader.cancel();
    return _player.stop();
  }
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  // Fires each time the clip finishes playing.
  Stream<void> get onComplete => _player.processingStateStream
      .where((s) => s == ProcessingState.completed)
      .map((_) {});

  Future<void> dispose() async => _player.dispose();
}
