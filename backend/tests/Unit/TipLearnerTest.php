<?php

namespace Tests\Unit;

use App\Models\TipLearning;
use App\Services\TipLearner;
use PHPUnit\Framework\TestCase;

class TipLearnerTest extends TestCase
{
    public function test_arms_name_the_setting_and_the_direction(): void
    {
        $this->assertSame('reading_speed:down', TipLearner::arm('reading_speed', 1.0, 0.8));
        $this->assertSame('text_scale:up', TipLearner::arm('text_scale', 1.0, 1.3));
        $this->assertSame('auto_play_next:off', TipLearner::arm('auto_play_next', true, false));
        $this->assertSame('narrator_voice:warm_male', TipLearner::arm('narrator_voice', 'calm_female', 'warm_male'));
    }

    public function test_beta_draws_centre_on_the_belief(): void
    {
        mt_srand(42);
        $draws = [];
        for ($i = 0; $i < 4000; $i++) {
            $draws[] = TipLearner::sampleBeta(8, 2);
        }
        $mean = array_sum($draws) / count($draws);
        $this->assertEqualsWithDelta(0.8, $mean, 0.02); // Beta(8, 2) has mean 0.8
        $this->assertGreaterThan(0.0, min($draws));
        $this->assertLessThan(1.0, max($draws));
    }

    public function test_unsure_beliefs_spread_out_more_than_sure_ones(): void
    {
        mt_srand(7);
        $spread = function (float $a, float $b): float {
            $xs = [];
            for ($i = 0; $i < 3000; $i++) {
                $xs[] = TipLearner::sampleBeta($a, $b);
            }
            $m = array_sum($xs) / count($xs);
            return sqrt(array_sum(array_map(fn ($x) => ($x - $m) ** 2, $xs)) / count($xs));
        };
        // Same mean (0.5), but 2 tries vs 40: the new tip still gets explored.
        $this->assertGreaterThan($spread(20, 20) * 2, $spread(1, 1));
    }

    public function test_a_child_borrows_a_little_of_what_everyone_learned(): void
    {
        $everyone = new TipLearning(['alpha' => 11.0, 'beta' => 1.0]);
        [$alpha, $beta] = TipLearner::combine(null, $everyone);
        $this->assertEqualsWithDelta(4.0, $alpha, 1e-9); // 1 + 0.3 x 10
        $this->assertEqualsWithDelta(1.0, $beta, 1e-9);

        $mine = new TipLearning(['alpha' => 1.0, 'beta' => 6.0]);
        [$alpha, $beta] = TipLearner::combine($mine, $everyone);
        $this->assertLessThan(0.5, $alpha / ($alpha + $beta)); // own evidence wins
    }

    public function test_outcomes_are_judged_by_a_clear_margin(): void
    {
        $this->assertSame('helped', TipLearner::judge(0.15, 5));
        $this->assertSame('worse', TipLearner::judge(-0.2, 5));
        $this->assertSame('no_change', TipLearner::judge(0.05, 5));
        $this->assertSame('unknown', TipLearner::judge(0.5, 0));
    }
}
