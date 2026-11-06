import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/* Piano sounds made in code - no audio assets to ship.

   Each key is a few harmonics with a fast attack and a decay that dies
   faster for the higher harmonics, which is roughly what a struck string
   does. The same samples are used for live playing (written to small WAV
   files) and for turning a recording into one long track. */
class PianoSynth {
  PianoSynth._();

  static const int sampleRate = 44100;

  // How long each key rings for.
  static const Duration noteLength = Duration(milliseconds: 1600);

  // C major, middle C (C4) up to C5: do re mi fa so la ti do.
  static const List<double> frequencies = [
    261.63, 293.66, 329.63, 349.23, 392.00, 440.00, 493.88, 523.25,
  ];

  static int get _noteSamples =>
      sampleRate * noteLength.inMilliseconds ~/ 1000;

  // One key's sound, peak around 0.5 so a few keys together still fit.
  static Float32List renderNote(double freq) {
    final n = _noteSamples;
    final out = Float32List(n);
    const attack = 0.004; // seconds
    const release = 0.12; // fade at the very end, so nothing clicks
    const harmonics = 7;
    // Slight inharmonicity, like a real string.
    const stiffness = 0.0004;
    // Lower notes ring a little longer.
    final baseDecay = 2.2 + (freq - 260) / 260 * 1.2;

    var peak = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      var v = 0.0;
      for (var h = 1; h <= harmonics; h++) {
        final f = freq * h * math.sqrt(1 + stiffness * h * h);
        final amp = 1 / math.pow(h, 1.4);
        final decay = math.exp(-t * baseDecay * (1 + 0.45 * (h - 1)));
        // Two strings a hair apart give the warm "chorus" of a piano.
        v += amp *
            decay *
            (math.sin(2 * math.pi * f * t) +
                0.6 * math.sin(2 * math.pi * (f + 0.35 * h) * t));
      }
      // A soft thump at the start for the hammer.
      v += 0.25 * math.exp(-t * 60) * math.sin(2 * math.pi * freq * 0.5 * t);

      var env = 1.0;
      if (t < attack) env = t / attack;
      final remaining = (n - i) / sampleRate;
      if (remaining < release) env *= remaining / release;

      v *= env;
      out[i] = v;
      if (v.abs() > peak) peak = v.abs();
    }
    final gain = peak == 0 ? 0 : 0.5 / peak;
    for (var i = 0; i < n; i++) {
      out[i] *= gain;
    }
    return out;
  }

  /* Writes each key's sound to a WAV file in the temp folder and returns
     the paths in key order. Rendered off the UI thread. */
  static Future<List<String>> prepareNoteFiles() async {
    final dir = await getTemporaryDirectory();
    final folder = Directory('${dir.path}/piano_notes');
    await folder.create(recursive: true);
    final paths = [
      for (var i = 0; i < frequencies.length; i++) '${folder.path}/note_$i.wav',
    ];
    if (await Future.wait(paths.map((p) => File(p).exists()))
        .then((all) => all.every((e) => e))) {
      return paths;
    }
    await Isolate.run(() {
      for (var i = 0; i < frequencies.length; i++) {
        File(paths[i]).writeAsBytesSync(encodeWav(toPcm16(renderNote(frequencies[i]))));
      }
    });
    return paths;
  }

  /* Mixes the recorded key presses into one track. The track runs for the
     recorded time, or a little longer so the last key can ring out. */
  static Future<PianoMix> mixRecording(
    List<PianoNoteEvent> events,
    Duration recorded,
  ) {
    return Isolate.run(() {
      final notes = [for (final f in frequencies) renderNote(f)];
      var endMs = recorded.inMilliseconds;
      for (final e in events) {
        endMs = math.max(endMs, e.at.inMilliseconds + noteLength.inMilliseconds);
      }
      final total = sampleRate * endMs ~/ 1000;
      final mix = Float32List(total);
      for (final e in events) {
        final start = sampleRate * e.at.inMilliseconds ~/ 1000;
        final note = notes[e.key];
        final len = math.min(note.length, total - start);
        for (var i = 0; i < len; i++) {
          mix[start + i] += note[i];
        }
      }
      // Soft limiter - many keys at once get rounded off instead of clipping.
      for (var i = 0; i < total; i++) {
        final v = mix[i];
        mix[i] = v.abs() <= 0.6 ? v : v.sign * (0.6 + 0.4 * _tanh((v.abs() - 0.6) / 0.4));
      }
      final pcm = toPcm16(mix);
      return PianoMix(
        pcm: pcm,
        duration: Duration(milliseconds: endMs),
        peaks: _peaks(mix, 160),
      );
    });
  }

  static double _tanh(double x) {
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }

  // Loudness of each slice of the track (0-1), for the waveform bars.
  static Float32List _peaks(Float32List samples, int buckets) {
    final out = Float32List(buckets);
    if (samples.isEmpty) return out;
    final size = (samples.length / buckets).ceil();
    var max = 0.0;
    for (var b = 0; b < buckets; b++) {
      final from = b * size;
      final to = math.min(from + size, samples.length);
      var sum = 0.0;
      for (var i = from; i < to; i++) {
        sum += samples[i] * samples[i];
      }
      final rms = to > from ? math.sqrt(sum / (to - from)) : 0.0;
      out[b] = rms;
      if (rms > max) max = rms;
    }
    if (max > 0) {
      for (var b = 0; b < buckets; b++) {
        out[b] /= max;
      }
    }
    return out;
  }

  static Int16List toPcm16(Float32List samples) {
    final out = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      out[i] = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return out;
  }

  // 16-bit mono WAV.
  static Uint8List encodeWav(Int16List pcm) {
    final dataBytes = pcm.length * 2;
    final b = ByteData(44 + dataBytes);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    b.setUint32(4, 36 + dataBytes, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, 1, Endian.little); // mono
    b.setUint32(24, sampleRate, Endian.little);
    b.setUint32(28, sampleRate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    b.setUint32(40, dataBytes, Endian.little);
    for (var i = 0; i < pcm.length; i++) {
      b.setInt16(44 + i * 2, pcm[i], Endian.little);
    }
    return b.buffer.asUint8List();
  }
}

// A key pressed during a recording, [at] from the start of the recording.
class PianoNoteEvent {
  final int key;
  final Duration at;
  const PianoNoteEvent(this.key, this.at);
}

// A finished recording, ready to play and save.
class PianoMix {
  final Int16List pcm;
  final Duration duration;
  // Loudness per slice (0-1), drawn as the waveform.
  final Float32List peaks;
  const PianoMix({required this.pcm, required this.duration, required this.peaks});
}
