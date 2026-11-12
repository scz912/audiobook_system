<?php

namespace App\Services;

use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Process;

/* Measures a music track's rhythm and sound from the audio itself, so the
   AI's genre and emotion tags rest on real numbers, not only on what it
   thinks it hears:

   - tempo (beats per minute) and how steady the pulse is - how regularly
     notes and hits fall, which a soft piano arpeggio can have as much as a
     drum kit, so it says nothing about how hard the beat hits,
   - how busy it is (new notes or hits a second),
   - how loud it is, how much the loudness swings, and any sudden loud
     jumps (a sensory risk),
   - how bright or dark it sounds.

   ffmpeg decodes the track to plain mono samples; everything else is done
   here in PHP, so no extra tools or services are needed.

   How the beat is found: the sound is cut into ~12 ms frames. Wherever the
   energy jumps up (a note or a drum hit starting) the "onset strength"
   rises. A steady beat makes those jumps repeat at a fixed gap, so
   comparing the onset strength with itself shifted by every gap between
   50 and 200 BPM (autocorrelation) shows a clear peak at the beat's gap.
   How high that peak is says how steady the pulse is. Tempos near 120 BPM
   are slightly preferred, which stops a fast hi-hat being read as double
   the real tempo.

   These numbers are evidence, not the answer: whether a steady 120 BPM
   feels upbeat (a pop song) or slow (gentle arpeggios under rain) depends
   on how it sounds, so the AI, which also hears the track, makes those
   calls. Checked on the built-in tracks: the kids' pop songs and the sleep
   music with rain both have a steady pulse. */
class AudioRhythmAnalyzer
{
    // Decode at a low rate: plenty for rhythm, and quick to work through.
    public const RATE = 11025;
    // Samples a frame: ~11.6 ms, so ~86 frames a second.
    private const HOP = 128;
    // Only the first few minutes are needed to know a track's character.
    private const MAX_SECONDS = 180;
    private const MIN_SECONDS = 5;

    private const MIN_BPM = 50;
    private const MAX_BPM = 200;

    // Pulse clarity (0-1) at or above which the pulse counts as steady / loose.
    public const STEADY_PULSE = 0.30;
    public const LOOSE_PULSE = 0.12;

    // Loudness windows for the loudness numbers and sudden jumps.
    private const WINDOW_SECONDS = 0.4;
    // A window this much louder than the few seconds before it is a jump.
    private const JUMP_DB = 10.0;

    /* Decode [path] with ffmpeg and measure it. Null if ffmpeg is missing,
       fails, or the track is too short to judge. */
    public function analyseFile(string $path): ?array
    {
        try {
            $result = Process::timeout(120)->run([
                config('services.ffmpeg.path'), '-v', 'error',
                '-i', $path,
                '-t', (string) self::MAX_SECONDS,
                '-ac', '1', '-ar', (string) self::RATE,
                '-f', 's16le', '-acodec', 'pcm_s16le', '-',
            ]);
            if (!$result->successful()) {
                Log::warning('[Rhythm] decode failed', ['error' => mb_substr($result->errorOutput(), 0, 300)]);
                return null;
            }
            $features = $this->analysePcm($result->output());
            Log::info('[Rhythm] measured', $features ?? ['result' => 'too short']);
            return $features;
        } catch (\Throwable $e) {
            Log::warning('[Rhythm] exception', ['error' => $e->getMessage()]);
            return null;
        }
    }

    /* Measure raw 16-bit little-endian mono samples at [rate]. Null if
       there are fewer than a few seconds. */
    public function analysePcm(string $pcm, int $rate = self::RATE): ?array
    {
        $samples = intdiv(strlen($pcm), 2);
        $frames = intdiv($samples, self::HOP);
        $fps = $rate / self::HOP;
        if ($frames < self::MIN_SECONDS * $fps) {
            return null;
        }
        $seconds = $frames / $fps;

        /* Per frame: its energy, the energy of its changes (sample to
           sample - this picks out sharp attacks like drums and plucks), and
           how often it crosses zero (high = bright or hissy sound). */
        $energy = [];
        $edge = [];
        $crossings = [];
        $prev = 0.0;
        $bytesPerFrame = self::HOP * 2;
        for ($f = 0; $f < $frames; $f++) {
            $chunk = unpack('v*', substr($pcm, $f * $bytesPerFrame, $bytesPerFrame));
            $e = 0.0;
            $h = 0.0;
            $z = 0;
            foreach ($chunk as $u) {
                // Unsigned 16-bit to signed, scaled to -1..1.
                $x = ($u >= 32768 ? $u - 65536 : $u) / 32768;
                $e += $x * $x;
                $d = $x - $prev;
                $h += $d * $d;
                if (($x >= 0) !== ($prev >= 0)) {
                    $z++;
                }
                $prev = $x;
            }
            $energy[] = $e / self::HOP;
            $edge[] = $h / self::HOP;
            $crossings[] = $z;
        }

        $loudness = $this->loudness($energy, $fps);
        $silent = $loudness['loudness_db'] < -55;

        $onset = $this->onsetStrength($energy, $edge, $fps);
        [$bpm, $clarity] = $silent ? [null, 0.0] : $this->tempo($onset, $fps);
        $beat = $clarity >= self::STEADY_PULSE ? 'steady'
            : ($clarity >= self::LOOSE_PULSE ? 'loose' : 'none');

        return [
            'seconds'           => (int) round($seconds),
            // Only a pulse you can follow has a tempo worth showing.
            'bpm'               => $beat !== 'none' && $bpm !== null ? (int) round($bpm) : null,
            'bpm_estimate'      => $bpm !== null ? (int) round($bpm) : null,
            'beat'              => $beat,
            'beat_clarity'      => round($clarity, 2),
            'onsets_per_sec'    => $silent ? 0.0 : round($this->onsetRate($onset, $fps), 1),
            'loudness_db'       => $loudness['loudness_db'],
            'loudness_range_db' => $loudness['loudness_range_db'],
            'loud_jumps'        => $loudness['loud_jumps'],
            'brightness_hz'     => $this->brightness($crossings, $energy, $fps),
        ];
    }

    /* Emotion tags worked out from the rhythm alone, for when the AI can't
       listen (no key, quota used up, a failed call), so an upload is never
       left without emotions. Rough by design - a busy steady pulse reads as
       lively, little or no pulse as calm, a dark or swelling sound as
       mysterious - and replaced by the AI's tags on the next re-listen. */
    public static function fallbackEmotions(array $f): array
    {
        $busy = (float) ($f['onsets_per_sec'] ?? 0);
        $bpm = (int) ($f['bpm'] ?? 0);
        $beat = $f['beat'] ?? 'none';
        if ($beat === 'none' || $busy < 2) {
            return ['Calm', 'Peaceful', 'Gentle'];
        }
        if ($beat === 'steady' && $bpm >= 110 && $busy >= 3.5) {
            return ['Energetic', 'Upbeat', 'Playful'];
        }
        if (($f['brightness_hz'] ?? 1000) < 500 || ($f['loudness_range_db'] ?? 0) >= 15) {
            return ['Mysterious', 'Curious', 'Imaginative'];
        }
        return ['Gentle', 'Playful', 'Calm'];
    }

    // A sensory note from the measured loud jumps alone, or '' if none.
    public static function fallbackSensoryNote(array $f): string
    {
        $jumps = $f['loud_jumps'] ?? [];
        if (!$jumps) {
            return '';
        }
        $times = implode(', ', array_map(
            fn ($s) => sprintf('%d:%02d', intdiv($s, 60), $s % 60),
            $jumps,
        ));
        return "Has sudden loud moments around {$times}.";
    }

    /* The measurements as plain lines for the AI prompt. */
    public static function describe(array $f): string
    {
        $lines = ["- Length measured: {$f['seconds']} s"];

        $clarity = number_format($f['beat_clarity'], 2);
        $lines[] = match ($f['beat']) {
            'steady' => "- Pulse: steady and regular (clarity {$clarity} of 1), about {$f['bpm']} BPM",
            'loose'  => "- Pulse: loose or uneven (clarity {$clarity} of 1), about {$f['bpm']} BPM",
            default  => "- Pulse: none you can follow (clarity {$clarity} of 1) - free-flowing, like ambience, rain or a held sound",
        };
        if ($f['beat'] !== 'none') {
            $lines[] = '  (this is how regularly notes fall, not how hard they hit: gentle arpeggios'
                . ' can be just as steady as drums; and a measured BPM can be double or half'
                . ' the pulse a listener feels)';
        }

        $rate = $f['onsets_per_sec'];
        $busy = $rate >= 5 ? 'busy' : ($rate >= 2 ? 'moderate' : 'sparse');
        $lines[] = "- Notes and hits: about {$rate} new sounds a second ({$busy})";

        $range = $f['loudness_range_db'];
        $swing = $range >= 15 ? 'large swings' : ($range >= 8 ? 'some swells' : 'steady');
        $lines[] = "- Loudness: about {$f['loudness_db']} dBFS, varying by {$range} dB ({$swing})";

        if ($f['loud_jumps']) {
            $times = implode(', ', array_map(
                fn ($s) => sprintf('%d:%02d', intdiv($s, 60), $s % 60),
                $f['loud_jumps'],
            ));
            $lines[] = "- Sudden loud jumps at: {$times}";
        } else {
            $lines[] = '- Sudden loud jumps: none found';
        }

        $hz = $f['brightness_hz'];
        $tone = $hz >= 1500 ? 'bright or hissy' : ($hz >= 500 ? 'balanced' : 'warm and dark');
        $lines[] = "- Tone: {$tone} (zero-crossing estimate ~{$hz} Hz)";

        return implode("\n", $lines);
    }

    /* Onset strength per frame: how much the sound got louder than just
       before (in log terms, so quiet and loud music count alike), for the
       whole sound and for its sharp attacks, minus the local average so
       only the jumps stand out. */
    private function onsetStrength(array $energy, array $edge, float $fps): array
    {
        $n = count($energy);
        $flux = [0.0];
        $lastLow = log(1 + 1000 * $energy[0]);
        $lastHigh = log(1 + 1000 * $edge[0]);
        for ($t = 1; $t < $n; $t++) {
            $low = log(1 + 1000 * $energy[$t]);
            $high = log(1 + 1000 * $edge[$t]);
            $flux[] = max(0.0, $low - $lastLow) + max(0.0, $high - $lastHigh);
            $lastLow = $low;
            $lastHigh = $high;
        }

        // Subtract a running average over ~0.4 s.
        $half = max(1, (int) round(0.2 * $fps));
        $sum = 0.0;
        $count = 0;
        $out = [];
        $lo = 0;
        $hi = -1;
        for ($t = 0; $t < $n; $t++) {
            while ($hi < min($n - 1, $t + $half)) {
                $sum += $flux[++$hi];
                $count++;
            }
            while ($lo < $t - $half) {
                $sum -= $flux[$lo++];
                $count--;
            }
            $out[] = max(0.0, $flux[$t] - $sum / $count);
        }
        return $out;
    }

    /* [bpm, clarity]: the beat's tempo and how clear it is (0-1), from
       the autocorrelation of the onset strength. */
    private function tempo(array $onset, float $fps): array
    {
        $n = count($onset);
        $mean = array_sum($onset) / $n;
        $o = array_map(fn ($v) => $v - $mean, $onset);
        $power = 0.0;
        foreach ($o as $v) {
            $power += $v * $v;
        }
        $power /= $n;
        if ($power <= 1e-12) {
            return [null, 0.0];
        }

        $minLag = max(1, (int) floor(60 * $fps / self::MAX_BPM));
        $maxLag = min($n - 1, (int) ceil(60 * $fps / self::MIN_BPM));
        $r = [];
        for ($lag = $minLag - 1; $lag <= $maxLag + 1; $lag++) {
            $s = 0.0;
            for ($t = 0, $end = $n - $lag; $t < $end; $t++) {
                $s += $o[$t] * $o[$t + $lag];
            }
            $r[$lag] = ($s / ($n - $lag)) / $power;
        }

        // Prefer tempos near 120 BPM (one octave either side is half as likely).
        $best = null;
        $bestScore = -INF;
        for ($lag = $minLag; $lag <= $maxLag; $lag++) {
            // Only real peaks, not points on a slope.
            if ($r[$lag] < $r[$lag - 1] || $r[$lag] < $r[$lag + 1]) {
                continue;
            }
            $bpm = 60 * $fps / $lag;
            $prior = exp(-0.5 * (log($bpm / 120, 2) ** 2));
            $score = $r[$lag] * $prior;
            if ($score > $bestScore) {
                $bestScore = $score;
                $best = $lag;
            }
        }
        if ($best === null) {
            return [null, 0.0];
        }

        // Find the peak between frames (parabola through it and its neighbours).
        [$a, $b, $c] = [$r[$best - 1], $r[$best], $r[$best + 1]];
        $den = $a - 2 * $b + $c;
        $shift = abs($den) > 1e-12 ? max(-0.5, min(0.5, 0.5 * ($a - $c) / $den)) : 0.0;

        return [60 * $fps / ($best + $shift), max(0.0, min(1.0, $b))];
    }

    // New sounds a second: clear peaks in the onset strength, at least ~90 ms apart.
    private function onsetRate(array $onset, float $fps): float
    {
        $n = count($onset);
        $mean = array_sum($onset) / $n;
        $var = 0.0;
        foreach ($onset as $v) {
            $var += ($v - $mean) ** 2;
        }
        $threshold = $mean + 0.5 * sqrt($var / $n);
        $gap = (int) round(0.09 * $fps);
        $count = 0;
        $last = -$gap;
        for ($t = 1; $t < $n - 1; $t++) {
            $v = $onset[$t];
            if ($v > $threshold && $v >= $onset[$t - 1] && $v >= $onset[$t + 1] && $t - $last >= $gap) {
                $count++;
                $last = $t;
            }
        }
        return $count / ($n / $fps);
    }

    /* Typical loudness, how much it swings (loud parts vs quiet parts) and
       the times of sudden loud jumps, from ~0.4 s windows. */
    private function loudness(array $energy, float $fps): array
    {
        $size = max(1, (int) round(self::WINDOW_SECONDS * $fps));
        $windows = [];
        foreach (array_chunk($energy, $size) as $chunk) {
            $windows[] = 10 * log10(array_sum($chunk) / count($chunk) + 1e-10);
        }
        $sorted = $windows;
        sort($sorted);
        $pick = fn (float $q) => $sorted[(int) floor($q * (count($sorted) - 1))];
        $median = $pick(0.5);

        /* A jump: a window 10 dB louder than the 3 s before it, that is
           actually loud for this track (not just quiet after silence).
           Jumps within 5 s of each other count once. */
        $jumps = [];
        $before = (int) round(3 / self::WINDOW_SECONDS);
        for ($i = $before; $i < count($windows); $i++) {
            $power = 0.0;
            for ($j = $i - $before; $j < $i; $j++) {
                $power += 10 ** ($windows[$j] / 10);
            }
            $prior = 10 * log10($power / $before + 1e-10);
            if ($windows[$i] - $prior >= self::JUMP_DB && $windows[$i] >= $median - 3) {
                $at = (int) floor($i * self::WINDOW_SECONDS);
                if (!$jumps || $at - end($jumps) >= 5) {
                    $jumps[] = $at;
                }
            }
        }

        return [
            'loudness_db'       => (int) round($median),
            'loudness_range_db' => (int) round($pick(0.95) - $pick(0.10)),
            'loud_jumps'        => array_slice($jumps, 0, 5),
        ];
    }

    /* Roughly the main pitch region, from how often the wave crosses zero
       (a crossing pair is one cycle). Only frames with real sound count. */
    private function brightness(array $crossings, array $energy, float $fps): int
    {
        $floor = max($energy) * 1e-4;
        $total = 0;
        $frames = 0;
        foreach ($crossings as $i => $z) {
            if ($energy[$i] > $floor) {
                $total += $z;
                $frames++;
            }
        }
        if ($frames === 0) {
            return 0;
        }
        return (int) round(($total / $frames) * $fps / 2);
    }
}
