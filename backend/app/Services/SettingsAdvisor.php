<?php

namespace App\Services;

use Carbon\Carbon;

/* Suggests setting changes for a child from their own listening sessions.
   No AI: a small set of rules, each backed by evidence, so every tip can
   say exactly why it was made.

   1. Recent sessions count more. Each session is weighted by
      0.5 ^ (age in days / 7), so last week counts twice as much as the
      week before (HALF_LIFE_DAYS).

   2. What the child chose beats what we guess. The player's icon buttons
      let a child change speed, text size and voice for one book; a session
      records the value only when they changed it. If they change it often
      enough (CHOICE_SHARE of sessions) and keep choosing the same way,
      that becomes the suggestion:
        - speed / text size: the weighted median of their choices, if it
          differs from the saved value by at least STEP and most choices
          lean the same way (AGREEMENT);
        - voice: the voice most of their choices went to.

   3. Otherwise, signs of struggle or rushing, per page read:
        - struggle = going back a page, pausing a lot, or stopping before
          halfway. Much of it -> read a little slower, highlight the words
          (read-along), and turn pages by hand if auto-turn is on;
        - tapping Next on almost every page while auto-turn is off -> turn
          auto-turn on; skipping ahead even with auto-turn on, while still
          finishing books -> read a little faster.
        - mostly sleepy moods -> a calmer pace.

   Each rule needs MIN_SESSIONS sessions with the data it uses. Every tip
   gets a strength (0-1); the strongest MAX_TIPS are kept, one per
   setting. Reasons are short, plain and in English and Malay. */
class SettingsAdvisor
{
    public const HALF_LIFE_DAYS = 7.0;
    public const WINDOW_DAYS = 30;
    public const MIN_SESSIONS = 3;
    public const MAX_TIPS = 3;
    // Below this many sessions, tips are shown as "low confidence".
    public const CONFIDENT_SESSIONS = 5;

    // Smallest change worth suggesting for speed and text size.
    public const STEP = 0.1;
    // Share of (weighted) sessions that must lean the same way.
    public const AGREEMENT = 0.6;
    // Share of (weighted) sessions with a choice before choices count.
    public const CHOICE_SHARE = 0.3;

    // Per-page / per-minute levels that count as "a lot".
    public const BACK_PER_PAGE = 0.25;
    public const PAUSES_PER_MINUTE = 1.5;
    public const NEXT_TAPS_PER_PAGE = 0.8;
    public const STRUGGLE = 0.4;

    public const SPEED_MIN = 0.6;
    public const SPEED_MAX = 1.5;

    /**
     * @param  iterable  $sessions  listening_history rows (models or arrays)
     * @param  array  $current  the child's saved settings
     * @param  int|null  $limit  how many tips to keep (null = every candidate)
     * @return array{items: array, stats: array, confidence: string}
     */
    public function advise(iterable $sessions, array $current, ?Carbon $now = null, ?int $limit = self::MAX_TIPS): array
    {
        $now ??= Carbon::now();
        $rows = $this->prepare($sessions, $now);
        $stats = $this->stats($rows);

        $tips = array_filter([
            $this->speedTip($rows, $current, $stats),
            $this->textTip($rows, $current),
            $this->voiceTip($rows, $current),
            $this->autoTurnTip($current, $stats),
            $this->readAlongTip($current, $stats),
        ]);

        usort($tips, fn ($a, $b) => $b['strength'] <=> $a['strength']);
        if ($limit !== null) {
            $tips = array_slice($tips, 0, $limit);
        }

        return [
            'items'      => array_values($tips),
            'stats'      => $stats,
            'confidence' => $stats['sessions_count'] < self::CONFIDENT_SESSIONS ? 'low' : 'normal',
        ];
    }

    /* The listening numbers alone (completion, struggle...), for judging
       whether an applied tip helped. */
    public function summarize(iterable $sessions, ?Carbon $now = null): array
    {
        return $this->stats($this->prepare($sessions, $now ?? Carbon::now()));
    }

    /* One number for "how well listening is going", 0 to 1: books finished,
       less struggle. Compared before and after a tip. */
    public static function wellbeing(array $stats): float
    {
        return round(0.5 * ($stats['completion_rate'] ?? 0) + 0.5 * (1 - ($stats['struggle'] ?? 0)), 3);
    }

    // ---- Inputs ----

    // Sessions from the window, each with its weight and per-page numbers.
    private function prepare(iterable $sessions, Carbon $now): array
    {
        $rows = [];
        foreach ($sessions as $s) {
            $at = data_get($s, 'created_at');
            $at = $at instanceof Carbon ? $at : Carbon::parse($at ?? $now);
            $age = max(0.0, $at->diffInSeconds($now, false) / 86400);
            if ($age > self::WINDOW_DAYS) {
                continue;
            }
            $seconds = (int) data_get($s, 'duration_seconds', 0);
            $total = data_get($s, 'pages_total');
            $reached = data_get($s, 'pages_reached');
            $pages = $total !== null && $reached !== null && (int) $total > 0;
            $rows[] = [
                'w'          => 0.5 ** ($age / self::HALF_LIFE_DAYS),
                'minutes'    => max($seconds / 60, 0.5),
                'completed'  => (bool) data_get($s, 'completed', false),
                'pauses'     => (int) data_get($s, 'pause_count', 0),
                'next_taps'  => (int) data_get($s, 'skip_count', 0),
                'backs'      => (int) data_get($s, 'back_count', 0),
                'has_pages'  => $pages,
                'reached'    => $pages ? max(1, (int) $reached) : null,
                'progress'   => $pages ? min(1.0, (int) $reached / (int) $total) : null,
                'speed'      => $this->num(data_get($s, 'speed_used')),
                'text'       => $this->num(data_get($s, 'text_scale_used')),
                'voice'      => data_get($s, 'voice_used') ?: null,
                'mood'       => data_get($s, 'mood'),
            ];
        }
        return $rows;
    }

    // Weighted rates over the sessions, shown to the caregiver as well.
    private function stats(array $rows): array
    {
        $paged = array_filter($rows, fn ($r) => $r['has_pages']);
        $moods = ['happy' => 0, 'calm' => 0, 'curious' => 0, 'sleepy' => 0];
        foreach ($rows as $r) {
            if (isset($moods[$r['mood']])) {
                $moods[$r['mood']]++;
            }
        }

        $earlyStops = $this->mean($paged, fn ($r) => !$r['completed'] && $r['progress'] < 0.5 ? 1.0 : 0.0);
        $backs = $this->mean($paged, fn ($r) => $r['backs'] / $r['reached']);
        $pauses = $this->mean($rows, fn ($r) => $r['pauses'] / $r['minutes']);
        $struggle = $paged === [] ? 0.0 : (
            min(1.0, $backs / self::BACK_PER_PAGE) * 0.4
            + min(1.0, $pauses / self::PAUSES_PER_MINUTE) * 0.3
            + $earlyStops * 0.3
        );

        return [
            'window_days'          => self::WINDOW_DAYS,
            'sessions_count'       => count($rows),
            'sessions_with_pages'  => count($paged),
            'completion_rate'      => round($this->mean($rows, fn ($r) => $r['completed'] ? 1.0 : 0.0), 3),
            'early_stop_rate'      => round($earlyStops, 3),
            'back_per_page'        => round($backs, 3),
            'next_taps_per_page'   => round($this->mean($paged, fn ($r) => $r['next_taps'] / $r['reached']), 3),
            'pauses_per_minute'    => round($pauses, 3),
            'struggle'             => round($struggle, 3),
            'sleepy_share'         => count($rows) ? round($moods['sleepy'] / count($rows), 3) : 0.0,
            'mood_breakdown'       => $moods,
        ];
    }

    // ---- Rules ----

    private function speedTip(array $rows, array $current, array $stats): ?array
    {
        $now = (float) ($current['reading_speed'] ?? 1.0);

        // What they chose with the speed buttons.
        $chosen = $this->preferred($rows, 'speed', $now);
        if ($chosen !== null) {
            [$value, $strength] = $chosen;
            $value = $this->clamp($value, 0.5, 2.0);
            return $this->tip('reading_speed', $value, $strength, $value < $now
                ? ['You often slow it down.', 'Anda selalu memperlahankannya.']
                : ['You often speed it up.', 'Anda selalu melajukannya.']);
        }

        if ($stats['sessions_with_pages'] >= self::MIN_SESSIONS) {
            // Going back, pausing, stopping early: give more time.
            if ($stats['struggle'] >= self::STRUGGLE && $now - self::STEP >= self::SPEED_MIN - 1e-9) {
                return $this->tip('reading_speed', round($now - self::STEP, 2), $stats['struggle'],
                    ['Lots of going back and pausing. Slower may help.',
                     'Banyak berundur dan berhenti. Lebih perlahan mungkin membantu.']);
            }
            // Skipping ahead even with auto-turn on, yet finishing books.
            if (($current['auto_play_next'] ?? true)
                && $stats['next_taps_per_page'] >= 0.5
                && $stats['completion_rate'] >= 0.6
                && $stats['back_per_page'] < 0.1
                && $now + self::STEP <= self::SPEED_MAX + 1e-9) {
                return $this->tip('reading_speed', round($now + self::STEP, 2), 0.5 * $stats['completion_rate'],
                    ['You skip ahead a lot. A bit faster may suit you.',
                     'Anda kerap melangkau. Sedikit laju mungkin sesuai.']);
            }
        }

        // Mostly sleepy: a calmer pace.
        if ($stats['sessions_count'] >= self::MIN_SESSIONS && $stats['sleepy_share'] >= 0.5 && $now > 0.9) {
            return $this->tip('reading_speed', 0.9, 0.4 * $stats['sleepy_share'],
                ['You often feel sleepy. A calmer pace may help.',
                 'Anda kerap mengantuk. Rentak tenang mungkin membantu.']);
        }
        return null;
    }

    private function textTip(array $rows, array $current): ?array
    {
        $now = (float) ($current['text_scale'] ?? 1.0);
        $chosen = $this->preferred($rows, 'text', $now);
        if ($chosen === null) {
            return null;
        }
        [$value, $strength] = $chosen;
        $value = $this->clamp($value, 0.7, 2.0);
        return $this->tip('text_scale', $value, $strength, $value > $now
            ? ['You often make the words bigger.', 'Anda selalu membesarkan tulisan.']
            : ['You often make the words smaller.', 'Anda selalu mengecilkan tulisan.']);
    }

    private function voiceTip(array $rows, array $current): ?array
    {
        $now = $current['narrator_voice'] ?? null;
        $voiced = array_filter($rows, fn ($r) => $r['voice'] !== null);
        if (count($voiced) < self::MIN_SESSIONS) {
            return null;
        }

        $often = $this->choiceShare($rows, $voiced);
        if ($often < self::CHOICE_SHARE) {
            return null;
        }

        // The voice most of their choices went to (by weight).
        $byVoice = [];
        foreach ($voiced as $r) {
            $byVoice[$r['voice']] = ($byVoice[$r['voice']] ?? 0) + $r['w'];
        }
        arsort($byVoice);
        $top = array_key_first($byVoice);
        $agree = $byVoice[$top] / array_sum($byVoice);
        if ($top === $now || $agree < self::AGREEMENT) {
            return null;
        }
        return $this->tip('narrator_voice', $top, $agree * min(1.0, $often / 0.5),
            ['You usually switch to this voice.', 'Anda biasanya menukar ke suara ini.']);
    }

    private function autoTurnTip(array $current, array $stats): ?array
    {
        if ($stats['sessions_with_pages'] < self::MIN_SESSIONS) {
            return null;
        }
        $on = (bool) ($current['auto_play_next'] ?? true);
        // Tapping Next on nearly every page: let the app turn them.
        if (!$on && $stats['next_taps_per_page'] >= self::NEXT_TAPS_PER_PAGE && $stats['completion_rate'] >= 0.5) {
            return $this->tip('auto_play_next', true, 0.6,
                ['You tap Next on every page. Auto-turn can do it.',
                 'Anda tekan Seterusnya setiap halaman. Auto-pusing boleh bantu.']);
        }
        // Going back after the page turned by itself: turn by hand.
        if ($on && $stats['back_per_page'] >= self::BACK_PER_PAGE + 0.05) {
            return $this->tip('auto_play_next', false, min(1.0, $stats['back_per_page'] * 2),
                ['You often go back. Turn pages yourself instead.',
                 'Anda kerap berundur. Pusing halaman sendiri.']);
        }
        return null;
    }

    private function readAlongTip(array $current, array $stats): ?array
    {
        if (($current['read_along'] ?? true) || $stats['sessions_with_pages'] < self::MIN_SESSIONS) {
            return null;
        }
        if ($stats['struggle'] >= self::STRUGGLE || $stats['early_stop_rate'] >= 0.4) {
            return $this->tip('read_along', true, max($stats['struggle'], $stats['early_stop_rate']) * 0.9,
                ['Lit-up words help to follow the story.',
                 'Perkataan bercahaya membantu mengikut cerita.']);
        }
        return null;
    }

    // ---- Helpers ----

    /* The value the child keeps choosing for [field] (speed or text), as
       [value, strength], or null when there isn't a clear, big enough
       change from [now]. */
    private function preferred(array $rows, string $field, float $now): ?array
    {
        $used = array_values(array_filter($rows, fn ($r) => $r[$field] !== null));
        if (count($used) < self::MIN_SESSIONS) {
            return null;
        }
        $often = $this->choiceShare($rows, $used);
        if ($often < self::CHOICE_SHARE) {
            return null;
        }
        $median = $this->weightedMedian(array_map(fn ($r) => [$r[$field], $r['w']], $used));
        $value = round(round($median * 20) / 20, 2); // to the nearest 0.05
        if (abs($value - $now) < self::STEP - 1e-9) {
            return null;
        }
        $lower = $value < $now;
        $agree = $this->mean($used, fn ($r) => ($lower ? $r[$field] < $now - 1e-9 : $r[$field] > $now + 1e-9) ? 1.0 : 0.0);
        return $agree >= self::AGREEMENT ? [$value, $agree * min(1.0, $often / 0.5)] : null;
    }

    // Weighted share of all sessions that had a choice.
    private function choiceShare(array $rows, array $chosen): float
    {
        $all = array_sum(array_column($rows, 'w'));
        return $all > 0 ? array_sum(array_column($chosen, 'w')) / $all : 0.0;
    }

    private function weightedMedian(array $pairs): float
    {
        usort($pairs, fn ($a, $b) => $a[0] <=> $b[0]);
        $half = array_sum(array_column($pairs, 1)) / 2;
        $run = 0.0;
        foreach ($pairs as [$value, $weight]) {
            $run += $weight;
            if ($run >= $half) {
                return (float) $value;
            }
        }
        return (float) end($pairs)[0];
    }

    // Weighted mean of fn(row) over rows; 0 when there are none.
    private function mean(array $rows, callable $fn): float
    {
        $sum = 0.0;
        $weights = 0.0;
        foreach ($rows as $r) {
            $sum += $r['w'] * $fn($r);
            $weights += $r['w'];
        }
        return $weights > 0 ? $sum / $weights : 0.0;
    }

    private function tip(string $key, mixed $value, float $strength, array $reason): array
    {
        return [
            'setting_key'     => $key,
            'suggested_value' => $value,
            'reason'          => $reason[0],
            'reason_ms'       => $reason[1],
            'strength'        => round(max(0.0, min(1.0, $strength)), 3),
        ];
    }

    private function num(mixed $v): ?float
    {
        return is_numeric($v) ? (float) $v : null;
    }

    private function clamp(float $v, float $lo, float $hi): float
    {
        return max($lo, min($hi, $v));
    }
}
