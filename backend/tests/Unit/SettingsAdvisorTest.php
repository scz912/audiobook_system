<?php

namespace Tests\Unit;

use App\Services\SettingsAdvisor;
use Carbon\Carbon;
use PHPUnit\Framework\TestCase;

class SettingsAdvisorTest extends TestCase
{
    private Carbon $now;

    private const SAVED = [
        'narrator_voice' => 'calm_female',
        'reading_speed'  => 1.0,
        'text_scale'     => 1.0,
        'auto_play_next' => true,
        'read_along'     => true,
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->now = Carbon::parse('2026-11-14 12:00:00');
    }

    // A calm, finished session [daysAgo] days ago, with [extra] on top.
    private function session(float $daysAgo, array $extra = []): array
    {
        return $extra + [
            'created_at'       => $this->now->copy()->subHours((int) round($daysAgo * 24)),
            'duration_seconds' => 300,
            'completed'        => true,
            'pause_count'      => 0,
            'skip_count'       => 0,
            'back_count'       => 0,
            'pages_total'      => 8,
            'pages_reached'    => 8,
            'mood'             => 'calm',
        ];
    }

    private function advise(array $sessions, array $saved = []): array
    {
        return (new SettingsAdvisor())->advise($sessions, $saved + self::SAVED, $this->now);
    }

    private function tip(array $advice, string $key): ?array
    {
        foreach ($advice['items'] as $item) {
            if ($item['setting_key'] === $key) {
                return $item;
            }
        }
        return null;
    }

    public function test_a_child_who_keeps_slowing_down_gets_that_speed(): void
    {
        $advice = $this->advise([
            $this->session(0, ['speed_used' => 0.8]),
            $this->session(1, ['speed_used' => 0.8]),
            $this->session(2, ['speed_used' => 0.75]),
            $this->session(3),
            $this->session(4, ['speed_used' => 0.8]),
        ]);

        $tip = $this->tip($advice, 'reading_speed');
        $this->assertNotNull($tip);
        $this->assertEqualsWithDelta(0.8, $tip['suggested_value'], 0.001);
        $this->assertSame('You often slow it down.', $tip['reason']);
        $this->assertNotEmpty($tip['reason_ms']);
        $this->assertSame('normal', $advice['confidence']);
    }

    public function test_text_size_and_voice_choices_become_tips(): void
    {
        $advice = $this->advise([
            $this->session(0, ['text_scale_used' => 1.4, 'voice_used' => 'warm_male']),
            $this->session(1, ['text_scale_used' => 1.4, 'voice_used' => 'warm_male']),
            $this->session(2, ['text_scale_used' => 1.3, 'voice_used' => 'warm_male']),
        ]);

        $this->assertEqualsWithDelta(1.4, $this->tip($advice, 'text_scale')['suggested_value'], 0.001);
        $this->assertSame('warm_male', $this->tip($advice, 'narrator_voice')['suggested_value']);
        $this->assertSame('low', $advice['confidence']); // only 3 sessions
    }

    public function test_recent_choices_outweigh_old_ones(): void
    {
        $advice = $this->advise([
            $this->session(0, ['speed_used' => 0.8]),
            $this->session(1, ['speed_used' => 0.8]),
            $this->session(2, ['speed_used' => 0.8]),
            $this->session(20, ['speed_used' => 1.3]),
            $this->session(21, ['speed_used' => 1.3]),
            $this->session(22, ['speed_used' => 1.3]),
        ]);

        $this->assertEqualsWithDelta(0.8, $this->tip($advice, 'reading_speed')['suggested_value'], 0.001);
    }

    public function test_rare_choices_are_not_enough(): void
    {
        $sessions = [];
        for ($i = 0; $i < 12; $i++) {
            // 3 choices spread among 12 sessions: not a habit yet.
            $sessions[] = $this->session($i * 0.5, in_array($i, [2, 6, 10], true) ? ['speed_used' => 0.7] : []);
        }

        $this->assertNull($this->tip($this->advise($sessions), 'reading_speed'));
    }

    public function test_struggling_suggests_slower_lit_up_words_and_turning_by_hand(): void
    {
        $struggle = ['completed' => false, 'pages_reached' => 3, 'back_count' => 2, 'pause_count' => 6];
        $advice = $this->advise([
            $this->session(0, $struggle),
            $this->session(1, $struggle),
            $this->session(2, $struggle),
            $this->session(3, $struggle),
        ], ['read_along' => false]);

        $this->assertEqualsWithDelta(0.9, $this->tip($advice, 'reading_speed')['suggested_value'], 0.001);
        $this->assertTrue($this->tip($advice, 'read_along')['suggested_value']);
        $this->assertFalse($this->tip($advice, 'auto_play_next')['suggested_value']);
        $this->assertGreaterThanOrEqual(0.4, $advice['stats']['struggle']);
    }

    public function test_older_sessions_without_page_details_still_count(): void
    {
        $old = ['pages_total' => null, 'pages_reached' => null, 'completed' => false, 'pause_count' => 10];
        $advice = $this->advise([
            $this->session(0, $old), $this->session(1, $old), $this->session(2, $old),
        ]);

        $tip = $this->tip($advice, 'reading_speed');
        $this->assertEqualsWithDelta(0.9, $tip['suggested_value'], 0.001);
        $this->assertSame(0, $advice['stats']['sessions_with_pages']);
    }

    public function test_tapping_next_on_every_page_suggests_auto_turn(): void
    {
        $tapper = ['skip_count' => 7];
        $advice = $this->advise([
            $this->session(0, $tapper),
            $this->session(1, $tapper),
            $this->session(2, $tapper),
        ], ['auto_play_next' => false]);

        $this->assertTrue($this->tip($advice, 'auto_play_next')['suggested_value']);
    }

    public function test_happy_listening_gives_no_tips(): void
    {
        $advice = $this->advise([
            $this->session(0), $this->session(1), $this->session(2),
            $this->session(3), $this->session(4), $this->session(5),
        ]);

        $this->assertSame([], $advice['items']);
        $this->assertSame(6, $advice['stats']['sessions_count']);
    }

    public function test_sessions_older_than_the_window_are_ignored(): void
    {
        $advice = $this->advise([
            $this->session(40, ['speed_used' => 0.7]),
            $this->session(41, ['speed_used' => 0.7]),
            $this->session(42, ['speed_used' => 0.7]),
        ]);

        $this->assertSame([], $advice['items']);
        $this->assertSame(0, $advice['stats']['sessions_count']);
    }

    public function test_never_more_than_three_tips(): void
    {
        $all = [
            'completed' => false, 'pages_reached' => 3, 'back_count' => 2, 'pause_count' => 6,
            'text_scale_used' => 1.5, 'voice_used' => 'warm_male',
        ];
        $advice = $this->advise(array_map(fn ($d) => $this->session($d, $all), [0, 1, 2, 3]), ['read_along' => false]);

        $this->assertCount(3, $advice['items']);
        $keys = array_column($advice['items'], 'setting_key');
        $this->assertSame($keys, array_unique($keys));
    }
}
