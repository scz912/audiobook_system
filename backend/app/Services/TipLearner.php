<?php

namespace App\Services;

use App\Models\ChildProfile;
use App\Models\TipLearning;
use App\Models\TipOutcome;
use Carbon\Carbon;

/* The learning part of the setting tips: a Thompson-sampling bandit.

   Each kind of tip is an "arm" (reading_speed:down, auto_play_next:on,
   narrator_voice:warm_male, ...). For every arm we keep a Beta(alpha, beta)
   belief of how likely it is to be a good tip, starting at Beta(1, 1)
   ("no idea"), one for each child and one for everyone.

   It learns from two kinds of feedback:
   - what the caregiver does with a tip: accepted -> alpha + 1,
     edited -> alpha + 0.5 (right idea, wrong amount), dismissed -> beta + 1;
   - whether an applied tip actually helped. When a tip is applied we save
     the child's listening "wellbeing" (books finished, less struggle).
     After MIN_SESSIONS_AFTER sessions (or WAIT_DAYS days with at least
     one) we compare: up by HELP_MARGIN or more -> alpha + 1.5, down by as
     much -> beta + 1.5. An outcome counts more than a tap.

   When ranking new tips, a child's own belief is used, plus everyone's
   shrunk by GLOBAL_WEIGHT (a new child borrows what worked for others).
   For each candidate we draw theta ~ Beta(alpha, beta): tips that worked
   tend to draw high, but an unsure arm sometimes draws high too, so it
   still gets tried (explore vs exploit). Its score mixes the rule's own
   strength with theta. Arms that have clearly not worked (mean below
   DISTRUST with EVIDENCE or more) are left out. */
class TipLearner
{
    public const GLOBAL_WEIGHT = 0.3;
    public const RULE_WEIGHT = 0.5;
    public const DISTRUST = 0.3;
    public const EVIDENCE = 4.0;

    public const MIN_SESSIONS_AFTER = 3;
    public const WAIT_DAYS = 14;
    public const HELP_MARGIN = 0.1;

    // Rewards.
    public const ACCEPTED = 1.0;
    public const EDITED = 0.5;
    public const DISMISSED = 1.0;
    public const OUTCOME = 1.5;

    /** @param bool $explore false = use the belief's mean instead of a random draw (tests). */
    public function __construct(private bool $explore = true)
    {
    }

    // The kind of tip: which setting, and which way it moves.
    public static function arm(string $key, mixed $current, mixed $value): string
    {
        if (is_bool($value)) {
            return "$key:" . ($value ? 'on' : 'off');
        }
        if (is_numeric($value) && is_numeric($current)) {
            return "$key:" . ((float) $value < (float) $current ? 'down' : 'up');
        }
        return "$key:" . (string) $value;
    }

    // ---- Ranking ----

    /* Scores [candidates] (each with setting_key, strength and arm) for
       [childId], drops ones that have clearly not worked, and returns them
       best first, each with a 'learning' summary for the UI. */
    public function rank(string $childId, array $candidates): array
    {
        $arms = array_values(array_unique(array_column($candidates, 'arm')));
        $mine = $this->beliefs($childId, $arms);
        $everyone = $this->beliefs(TipLearning::GLOBAL, $arms);

        $ranked = [];
        foreach ($candidates as $c) {
            $own = $mine[$c['arm']] ?? null;
            $all = $everyone[$c['arm']] ?? null;
            [$alpha, $beta] = self::combine($own, $all);
            $mean = $alpha / ($alpha + $beta);
            if ($mean < self::DISTRUST && ($alpha + $beta - 2) >= self::EVIDENCE) {
                continue; // tried enough, and it doesn't help
            }
            $theta = $this->explore ? self::sampleBeta($alpha, $beta) : $mean;
            $c['score'] = round(self::RULE_WEIGHT * $c['strength'] + (1 - self::RULE_WEIGHT) * $theta, 4);
            $c['learning'] = self::summary($own, $all, $mean);
            $ranked[] = $c;
        }
        usort($ranked, fn ($a, $b) => $b['score'] <=> $a['score']);
        return $ranked;
    }

    /* The child's belief plus everyone's, shrunk. Each starts at (1, 1), so
       only what was learned on top of that is borrowed. */
    public static function combine(?TipLearning $own, ?TipLearning $all): array
    {
        $alpha = ($own->alpha ?? 1.0) + self::GLOBAL_WEIGHT * (($all->alpha ?? 1.0) - 1.0);
        $beta = ($own->beta ?? 1.0) + self::GLOBAL_WEIGHT * (($all->beta ?? 1.0) - 1.0);
        return [$alpha, $beta];
    }

    // What the UI shows: how often it helped (this child first, else everyone).
    private static function summary(?TipLearning $own, ?TipLearning $all, float $mean): array
    {
        $source = ($own && ($own->helped + $own->not_helped) > 0) ? $own : $all;
        return [
            'trust'  => round($mean, 2),
            'helped' => (int) ($source->helped ?? 0),
            'tried'  => (int) (($source->helped ?? 0) + ($source->not_helped ?? 0)),
            'mine'   => $source === $own && $own !== null,
        ];
    }

    private function beliefs(string $scope, array $arms): array
    {
        if ($arms === []) {
            return [];
        }
        return TipLearning::where('scope', $scope)->whereIn('arm', $arms)->get()->keyBy('arm')->all();
    }

    // ---- Learning ----

    // A caregiver accepted, edited or dismissed a tip.
    public function recordFeedback(string $childId, string $arm, string $status): void
    {
        [$a, $b, $counter] = match ($status) {
            'accepted'  => [self::ACCEPTED, 0.0, 'accepted'],
            'edited'    => [self::EDITED, 0.0, 'edited'],
            'dismissed' => [0.0, self::DISMISSED, 'dismissed'],
            default     => [0.0, 0.0, null],
        };
        if ($counter === null) {
            return;
        }
        foreach ([$childId, TipLearning::GLOBAL] as $scope) {
            $this->bump($scope, $arm, $a, $b, $counter);
        }
    }

    // Remember an applied tip and how listening was going, to check later.
    public function startOutcome(string $childId, string $arm, array $baselineStats, ?Carbon $at = null): TipOutcome
    {
        return TipOutcome::create([
            'child_id'   => $childId,
            'arm'        => $arm,
            'applied_at' => $at ?? Carbon::now(),
            'baseline'   => [
                'wellbeing'      => SettingsAdvisor::wellbeing($baselineStats),
                'sessions_count' => $baselineStats['sessions_count'] ?? 0,
            ],
        ]);
    }

    /* Checks the child's applied tips that have had time to show an effect
       and learns from them. Returns how many were judged. */
    public function evaluateOutcomes(ChildProfile $profile, SettingsAdvisor $advisor, ?Carbon $now = null): int
    {
        $now ??= Carbon::now();
        $judged = 0;
        $open = TipOutcome::where('child_id', $profile->child_id)->whereNull('evaluated_at')->get();
        foreach ($open as $outcome) {
            $after = $profile->listeningHistory()
                ->where('created_at', '>', $outcome->applied_at)
                ->where('created_at', '<=', $outcome->applied_at->copy()->addDays(self::WAIT_DAYS))
                ->get();
            $waited = $outcome->applied_at->diffInDays($now, false) >= self::WAIT_DAYS;
            if ($after->count() < self::MIN_SESSIONS_AFTER && !($waited && $after->count() > 0)) {
                if ($waited) {
                    // Nothing listened to since: nothing to learn.
                    $outcome->update(['evaluated_at' => $now, 'result' => 'unknown']);
                }
                continue;
            }

            $before = (float) ($outcome->baseline['wellbeing'] ?? 0);
            $change = SettingsAdvisor::wellbeing($advisor->summarize($after, $now)) - $before;
            $result = self::judge($change, (int) ($outcome->baseline['sessions_count'] ?? 0));
            $outcome->update([
                'evaluated_at' => $now,
                'result'       => $result,
                'change'       => round($change, 3),
            ]);
            if ($result === 'helped' || $result === 'worse') {
                foreach ([$profile->child_id, TipLearning::GLOBAL] as $scope) {
                    $result === 'helped'
                        ? $this->bump($scope, $outcome->arm, self::OUTCOME, 0.0, 'helped')
                        : $this->bump($scope, $outcome->arm, 0.0, self::OUTCOME, 'not_helped');
                }
            }
            $judged++;
        }
        return $judged;
    }

    // Better, worse or about the same. No "before" to compare -> unknown.
    public static function judge(float $change, int $sessionsBefore): string
    {
        if ($sessionsBefore === 0) {
            return 'unknown';
        }
        if ($change >= self::HELP_MARGIN) {
            return 'helped';
        }
        return $change <= -self::HELP_MARGIN ? 'worse' : 'no_change';
    }

    private function bump(string $scope, string $arm, float $alpha, float $beta, string $counter): void
    {
        $row = TipLearning::firstOrCreate(['scope' => $scope, 'arm' => $arm]);
        $row->alpha += $alpha;
        $row->beta += $beta;
        $row->{$counter} += 1;
        $row->save();
    }

    // ---- Sampling ----

    // A random draw from Beta(alpha, beta), via two Gamma draws.
    public static function sampleBeta(float $alpha, float $beta): float
    {
        $x = self::sampleGamma($alpha);
        $y = self::sampleGamma($beta);
        return $x + $y > 0 ? $x / ($x + $y) : 0.5;
    }

    // Marsaglia and Tsang's method (with the shape < 1 boost).
    private static function sampleGamma(float $shape): float
    {
        if ($shape < 1) {
            return self::sampleGamma($shape + 1) * self::uniform() ** (1 / $shape);
        }
        $d = $shape - 1 / 3;
        $c = 1 / sqrt(9 * $d);
        while (true) {
            do {
                $x = self::normal();
                $v = 1 + $c * $x;
            } while ($v <= 0);
            $v = $v ** 3;
            $u = self::uniform();
            if ($u < 1 - 0.0331 * $x ** 4 || log($u) < 0.5 * $x ** 2 + $d * (1 - $v + log($v))) {
                return $d * $v;
            }
        }
    }

    private static function normal(): float
    {
        return sqrt(-2 * log(self::uniform())) * cos(2 * M_PI * self::uniform());
    }

    // Uniform in (0, 1), never exactly 0.
    private static function uniform(): float
    {
        return (mt_rand(1, mt_getrandmax()) - 0.5) / mt_getrandmax();
    }
}
