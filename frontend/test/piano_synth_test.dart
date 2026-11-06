import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:autism_audiobook/audio/piano_synth.dart';

/* The piano's sounds are made in code, so check they are real audio:
   loud enough, never clipping, and laid out where the keys were pressed. */
void main() {
  test('each key is audible and stays within range', () {
    for (final f in PianoSynth.frequencies) {
      final note = PianoSynth.renderNote(f);
      var peak = 0.0;
      for (final v in note) {
        if (v.abs() > peak) peak = v.abs();
      }
      expect(peak, closeTo(0.5, 0.01));
      // Fades to silence, so retriggering never clicks.
      expect(note.last.abs(), lessThan(0.001));
    }
  });

  test('a recording places notes at their times and lets the last ring', () async {
    final mix = await PianoSynth.mixRecording(
      const [
        PianoNoteEvent(0, Duration(milliseconds: 500)),
        PianoNoteEvent(4, Duration(milliseconds: 1500)),
      ],
      const Duration(seconds: 2),
    );
    // 1.5s + the note's 1.6s ring is longer than the 2s recorded.
    expect(mix.duration, const Duration(milliseconds: 3100));
    expect(mix.pcm.length, PianoSynth.sampleRate * 31 ~/ 10);

    int loudest(int fromMs, int toMs) {
      var m = 0;
      for (var i = PianoSynth.sampleRate * fromMs ~/ 1000;
          i < PianoSynth.sampleRate * toMs ~/ 1000;
          i++) {
        if (mix.pcm[i].abs() > m) m = mix.pcm[i].abs();
      }
      return m;
    }

    expect(loudest(0, 490), 0); // silence before the first key
    expect(loudest(500, 600), greaterThan(8000));
    expect(mix.peaks.reduce((a, b) => a > b ? a : b), 1);
  });

  test('many keys at once are limited instead of clipping', () async {
    final mix = await PianoSynth.mixRecording(
      [for (var k = 0; k < 8; k++) PianoNoteEvent(k, Duration.zero)],
      const Duration(seconds: 1),
    );
    var hardClipped = 0;
    for (final v in mix.pcm) {
      if (v.abs() >= 32767) hardClipped++;
    }
    expect(hardClipped, 0);
  });

  test('WAV header describes 16-bit mono at the synth rate', () {
    final wav = PianoSynth.encodeWav(Int16List.fromList([0, 1000, -1000]));
    final b = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(b.getUint16(22, Endian.little), 1);
    expect(b.getUint32(24, Endian.little), PianoSynth.sampleRate);
    expect(b.getUint16(34, Endian.little), 16);
    expect(b.getUint32(40, Endian.little), 6);
    expect(b.getInt16(46, Endian.little), 1000);
  });
}
