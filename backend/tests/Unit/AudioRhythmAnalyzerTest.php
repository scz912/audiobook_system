<?php

namespace Tests\Unit;

use App\Services\AudioRhythmAnalyzer;
use PHPUnit\Framework\TestCase;

/* The rhythm maths on made-up audio with known answers: click tracks at
   set tempos, rain-like noise with no beat, a sudden loud hit, silence. */
class AudioRhythmAnalyzerTest extends TestCase
{
    private const RATE = AudioRhythmAnalyzer::RATE;

    // Samples (-1..1) to 16-bit little-endian PCM.
    private function pcm(array $samples): string
    {
        $out = '';
        foreach ($samples as $x) {
            $out .= pack('v', (int) round(max(-1, min(1, $x)) * 32767) & 0xFFFF);
        }
        return $out;
    }

    /* [seconds] of quiet hum with a short tone burst on every beat at
       [bpm]; [offbeat] adds softer, brighter ticks halfway between beats
       (like a hi-hat). */
    private function beats(float $bpm, int $seconds, bool $offbeat = false): string
    {
        mt_srand(7);
        $n = $seconds * self::RATE;
        $s = [];
        for ($i = 0; $i < $n; $i++) {
            $s[] = 0.02 * sin(2 * M_PI * 220 * $i / self::RATE);
        }
        $gap = 60 / $bpm * self::RATE;
        $burst = (int) (0.04 * self::RATE);
        for ($b = 0.0; $b < $n; $b += $gap) {
            for ($k = 0; $k < $burst && $b + $k < $n; $k++) {
                $s[(int) $b + $k] += 0.7 * exp(-$k / ($burst / 4)) * sin(2 * M_PI * 600 * $k / self::RATE);
            }
            if ($offbeat) {
                $h = (int) ($b + $gap / 2);
                for ($k = 0; $k < $burst / 2 && $h + $k < $n; $k++) {
                    $s[$h + $k] += 0.25 * exp(-$k / ($burst / 8)) * (mt_rand() / mt_getrandmax() * 2 - 1);
                }
            }
        }
        return $this->pcm($s);
    }

    private function analyse(string $pcm): array
    {
        $f = (new AudioRhythmAnalyzer())->analysePcm($pcm);
        $this->assertNotNull($f);
        return $f;
    }

    public function test_finds_the_tempo_of_a_steady_beat(): void
    {
        foreach ([72, 100, 128] as $bpm) {
            $f = $this->analyse($this->beats($bpm, 30));
            $this->assertSame('steady', $f['beat'], "pulse at $bpm BPM");
            $this->assertEqualsWithDelta($bpm, $f['bpm'], 2, "tempo at $bpm BPM");
        }
    }

    public function test_offbeat_ticks_do_not_double_the_tempo(): void
    {
        $f = $this->analyse($this->beats(110, 30, offbeat: true));
        $this->assertEqualsWithDelta(110, $f['bpm'], 2);
        // Two sounds a beat: busier than the plain click track.
        $plain = $this->analyse($this->beats(110, 30));
        $this->assertGreaterThan($plain['onsets_per_sec'], $f['onsets_per_sec']);
    }

    public function test_rain_like_noise_has_no_beat_and_sounds_bright(): void
    {
        mt_srand(3);
        $s = [];
        for ($i = 0; $i < 30 * self::RATE; $i++) {
            $s[] = 0.2 * (mt_rand() / mt_getrandmax() * 2 - 1);
        }
        $f = $this->analyse($this->pcm($s));
        $this->assertSame('none', $f['beat']);
        $this->assertNull($f['bpm']);
        $this->assertGreaterThan(1500, $f['brightness_hz']);
        $this->assertSame([], $f['loud_jumps']);
        $this->assertLessThan(4, $f['loudness_range_db']);
    }

    public function test_finds_a_sudden_loud_moment(): void
    {
        $s = [];
        for ($i = 0; $i < 30 * self::RATE; $i++) {
            $t = $i / self::RATE;
            $amp = ($t >= 20 && $t < 21) ? 0.9 : 0.05;
            $s[] = $amp * sin(2 * M_PI * 330 * $t);
        }
        $f = $this->analyse($this->pcm($s));
        $this->assertCount(1, $f['loud_jumps']);
        $this->assertEqualsWithDelta(20, $f['loud_jumps'][0], 1);
        $this->assertStringContainsString('0:20', AudioRhythmAnalyzer::describe($f));
    }

    public function test_silence_and_short_clips(): void
    {
        $f = $this->analyse(str_repeat("\0\0", 10 * self::RATE));
        $this->assertSame('none', $f['beat']);
        $this->assertNull($f['bpm']);

        $this->assertNull((new AudioRhythmAnalyzer())->analysePcm(str_repeat("\0\0", 2 * self::RATE)));
    }

    public function test_fallback_labels_from_rhythm_alone(): void
    {
        // Lively: a quick steady beat with an offbeat tick.
        $lively = $this->analyse($this->beats(128, 30, offbeat: true));
        $this->assertSame(['Energetic', 'Upbeat', 'Playful'], AudioRhythmAnalyzer::fallbackEmotions($lively));

        // Calm: no pulse at all.
        mt_srand(3);
        $s = [];
        for ($i = 0; $i < 30 * self::RATE; $i++) {
            $s[] = 0.2 * (mt_rand() / mt_getrandmax() * 2 - 1);
        }
        $calm = $this->analyse($this->pcm($s));
        $this->assertSame(['Calm', 'Peaceful', 'Gentle'], AudioRhythmAnalyzer::fallbackEmotions($calm));
        $this->assertSame('', AudioRhythmAnalyzer::fallbackSensoryNote($calm));

        $this->assertSame(
            'Has sudden loud moments around 0:20, 1:32.',
            AudioRhythmAnalyzer::fallbackSensoryNote(['loud_jumps' => [20, 92]]),
        );
    }

    public function test_description_reads_plainly(): void
    {
        $f = $this->analyse($this->beats(100, 20));
        $text = AudioRhythmAnalyzer::describe($f);
        $this->assertStringContainsString('steady and regular', $text);
        $this->assertStringContainsString('BPM', $text);
        $this->assertStringContainsString('Sudden loud jumps: none found', $text);
    }
}
