import 'dart:async';

import 'package:just_audio/just_audio.dart';

/* Sensory-safety limits for audio (FR5, FR10, NFR5).

   Background music sits under the narration, so it has a hard ceiling it
   can never go above, and a lower level past which it starts to compete
   with the voice - caregivers are warned there before saving a book. */
class AudioSafety {
  AudioSafety._();

  /// Background music never plays louder than this (percent).
  static const int bgmCeiling = 60;

  /// Above this the music starts to compete with the narration (FR5).
  static const int bgmWarnAbove = 40;

  /// The level the one-tap fix lowers the music to (the default).
  static const int bgmRecommended = 30;

  /// How long starting and stopping audio fades take (NFR5: 300 ms or more).
  static const Duration fade = Duration(milliseconds: 400);

  /// A music level kept inside 0..[bgmCeiling].
  static int clampBgm(int percent) => percent.clamp(0, bgmCeiling);

  /// Whether a music level is high enough to warn about.
  static bool bgmTooLoud(int percent) => percent > bgmWarnAbove;
}

/* Fades a player in and out instead of starting or stopping it abruptly.
   A newer fade cancels an older one, so quick play/pause taps never leave
   the volume stuck half way. */
class AudioFader {
  AudioFader(this.player);

  final AudioPlayer player;
  int _gen = 0;

  /// Stop any fade in progress (call before disposing the player).
  void cancel() => _gen++;

  /* Ramp the volume to [target] (0..1). Returns false if a newer fade took
     over before this one finished. */
  Future<bool> rampTo(double target, {Duration duration = AudioSafety.fade}) async {
    final gen = ++_gen;
    final start = player.volume;
    const steps = 12;
    final step = Duration(microseconds: duration.inMicroseconds ~/ steps);
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(step);
      if (gen != _gen) return false;
      try {
        await player.setVolume(start + (target - start) * i / steps);
      } catch (_) {
        return false; // player gone
      }
    }
    return true;
  }

  /* Start playing from silence and fade up to [target]. If it is already
     playing, just fade to [target]. */
  Future<void> fadeInPlay(double target) async {
    if (!player.playing) {
      cancel();
      await player.setVolume(0);
      // play() completes only when playback ends, so don't await it.
      unawaited(player.play());
    }
    await rampTo(target);
  }

  /// Fade to silence, then pause.
  Future<void> fadeOutPause() async {
    if (!player.playing) return;
    if (await rampTo(0)) await player.pause();
  }
}
