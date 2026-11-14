<?php

namespace App\Services;

use Carbon\Carbon;

/* Recommends audiobooks for one child: a hybrid recommender built from
   the app's own listening data, with no outside service.

   1. Implicit ratings. Every (child, book) gets a rating from 0 to 1 from
      how they listened in the last WINDOW_DAYS days: finished = 1,
      otherwise how far they got (x 0.8), plus a little for re-reading.
      Below DISLIKED counts as "didn't like it". Recent listening counts
      more (half-life HALF_LIFE_DAYS).

   2. Content-based filtering. Each book is a weighted bag of features
      (category, topic words, tags, difficulty, format, language, the
      background music's genre and emotions), weighted by TF-IDF so
      common features count less. The child's taste profile is the sum of
      the books they rated, centred on NEUTRAL (liked books pull towards
      their features, disliked ones push away). A book scores by cosine
      similarity to that profile.

   3. Collaborative filtering (item-item). Books are compared by who
      listened to them across all children: "children who liked this
      also liked that" (cosine over ratings, at least MIN_CO_READERS
      children in common). Starter books are copies per family, so books
      are matched by the original they were copied from.

   4. Popularity: a Bayesian average rating over all children, for new
      children with no history yet (cold start).

   5. Context: today's mood (does the background music's emotion fit?),
      fit (difficulty just right for how they finish books, and the age
      group), and, if the person allowed it, their music taste (YouTube
      genres -> how well the background music suits them).

   The parts are mixed with weights that move from popularity to
   personal taste as history grows; parts with no data are left out and
   the rest re-weighted. Books just finished are pushed down (novelty).
   Finally MMR re-ranking (lambda MMR_LAMBDA) keeps the list varied, and
   each pick carries the reason that added most to its score. */
class BookRecommender
{
    public const WINDOW_DAYS = 90;
    public const HALF_LIFE_DAYS = 30.0;
    public const NEUTRAL = 0.4;
    public const DISLIKED = 0.3;
    public const MIN_CO_READERS = 2;
    public const PRIOR_COUNT = 3;
    public const MMR_LAMBDA = 0.75;
    public const FULL_HISTORY = 4;
    public const PERSONAL_SHARE = 1 / 3;

    public const MOOD_EMOTIONS = [
        'happy'   => ['Happy', 'Playful', 'Upbeat', 'Energetic', 'Whimsical'],
        'calm'    => ['Calm', 'Peaceful', 'Gentle', 'Soothing', 'Relaxing'],
        'curious' => ['Curious', 'Mysterious', 'Imaginative', 'Adventurous', 'Whimsical'],
        'sleepy'  => ['Calm', 'Soothing', 'Relaxing', 'Peaceful', 'Gentle'],
    ];
    public const MOOD_CLASHES = [
        'calm'   => ['Energetic', 'Upbeat'],
        'sleepy' => ['Energetic', 'Upbeat', 'Adventurous'],
    ];

    private const LEVELS = ['easy' => 0, 'medium' => 1, 'hard' => 2];
    private const STOPWORDS = [
        'a', 'an', 'the', 'my', 'and', 'of', 'to', 'in', 'on', 'with', 'for', 'at', 'is', 'are',
        'who', 'his', 'her', 'their', 'our', 'your', 'yang', 'dan', 'di', 'ke', 'saya', 'itu', 'ini',
    ];

    /**
     * @param  array  $books  candidates: id, canon, title, category, topic, tags, difficulty,
     *                        format, language, age_group, genre, emotions (list)
     * @param  array  $sessions  every child's sessions: child, canon, completed, progress (0-1|null), at
     * @param  array  $context  child, age, mood, taste (track genre => 0-1), limit
     */
    public function recommend(array $books, array $sessions, array $context, ?Carbon $now = null): array
    {
        $now ??= Carbon::now();
        // Only books that can be played: not still being made, not failed.
        $books = array_values(array_filter($books,
            fn ($b) => !in_array($b['status'] ?? 'available', ['processing', 'failed'], true)));
        if ($books === []) {
            return [];
        }
        $childId = $context['child'];
        $ratings = $this->ratings($sessions, $now);          // [child][canon] => [r, w, last, finishes]
        $mine = $ratings[$childId] ?? [];

        $vectors = $this->vectors($books);
        $byCanon = [];
        foreach ($books as $i => $b) {
            $byCanon[$b['canon']] ??= $i;
        }
        $profile = $this->profile($mine, $byCanon, $vectors);
        $similar = $this->itemSimilarity($ratings);
        $popularity = $this->popularity($ratings);
        $level = $this->comfortLevel($mine, $books, $byCanon);
        $history = min(1.0, count($mine) / self::FULL_HISTORY);

        $weights = [
            'content'       => 0.30 * $history,
            'collaborative' => 0.20 * $history,
            'popular'       => 0.10 + 0.25 * (1 - $history),
            'mood'          => 0.15,
            'fit'           => 0.15,
            'taste'         => 0.15,
        ];

        $scored = [];
        foreach ($books as $i => $b) {
            $parts = [
                'content'       => $profile ? $this->contentScore($profile, $vectors[$i]) : null,
                'collaborative' => $this->collaborativeScore($b['canon'], $mine, $similar),
                'popular'       => $popularity[$b['canon']] ?? null,
                'mood'          => $this->moodFit($b['emotions'] ?? [], $context['mood'] ?? null),
                'fit'           => $this->fit($b, $level, $context['age'] ?? null),
                'taste'         => isset($context['taste']) && $context['taste'] !== [] && ($b['genre'] ?? null)
                    ? (float) ($context['taste'][$b['genre']] ?? 0.0)
                    : null,
            ];
            $sum = 0.0;
            $total = 0.0;
            $contrib = [];
            foreach ($parts as $name => $value) {
                if ($value === null || $weights[$name] <= 0) {
                    continue;
                }
                $sum += $weights[$name] * $value;
                $total += $weights[$name];
                $contrib[$name] = $weights[$name] * $value;
            }
            $score = $total > 0 ? $sum / $total : 0.0;

            // Novelty: just finished -> later. A favourite comes back after a while.
            $own = $mine[$b['canon']] ?? null;
            if ($own && $own['finishes'] > 0 && $own['last']->diffInDays($now, false) < 2) {
                $score *= 0.6;
            }
            $scored[] = [
                'index'      => $i,
                'id'         => $b['id'],
                'score'      => $score,
                'parts'      => array_map(fn ($v) => $v === null ? null : round($v, 3), $parts),
                'new'        => $own === null,
            ];
        }

        /* Why each book: the part that lifts it most above the other books
           on offer (weight x (its value - that part's average over books
           not read yet)), so a part that is the same for every book never
           becomes the reason. */
        $pool = array_filter($scored, fn ($s) => $s['new']);
        $pool = count($pool) >= 2 ? $pool : $scored;
        $means = [];
        foreach (array_keys($weights) as $name) {
            $values = array_filter(array_column(array_column($pool, 'parts'), $name), fn ($v) => $v !== null);
            $means[$name] = $values ? array_sum($values) / count($values) : 0.0;
        }
        foreach ($scored as &$s) {
            $lift = [];
            $raw = [];
            foreach ($s['parts'] as $name => $value) {
                if ($value !== null && $weights[$name] > 0) {
                    $lift[$name] = $weights[$name] * ($value - $means[$name]);
                    $raw[$name] = $weights[$name] * $value;
                }
            }
            // Nothing stands out: fall back to what added most.
            if (max([0.0, ...array_values($lift)]) <= 1e-6) {
                $lift = $raw;
            }
            $s['reason'] = $this->reason($lift, $books[$s['index']], $mine, $books, $byCanon, $vectors, $similar, $context);
        }
        unset($s);

        return $this->diversify($scored, $vectors, (int) ($context['limit'] ?? 3));
    }

    // ---- 1. Implicit ratings ----

    private function ratings(array $sessions, Carbon $now): array
    {
        $out = [];
        foreach ($sessions as $s) {
            $at = $s['at'] instanceof Carbon ? $s['at'] : Carbon::parse($s['at']);
            $age = max(0.0, $at->diffInSeconds($now, false) / 86400);
            if ($age > self::WINDOW_DAYS) {
                continue;
            }
            $progress = $s['completed'] ? 1.0 : (isset($s['progress']) ? (float) $s['progress'] : 0.5);
            $r = $s['completed'] ? 1.0 : 0.8 * $progress;
            $cur = $out[$s['child']][$s['canon']] ?? ['r' => 0.0, 'w' => 0.0, 'last' => $at, 'finishes' => 0];
            $cur['r'] = max($cur['r'], $r);
            $cur['w'] = max($cur['w'], 0.5 ** ($age / self::HALF_LIFE_DAYS));
            $cur['last'] = $at->greaterThan($cur['last']) ? $at : $cur['last'];
            $cur['finishes'] += $s['completed'] ? 1 : 0;
            $out[$s['child']][$s['canon']] = $cur;
        }
        // Re-reading a book is a strong "I like this".
        foreach ($out as $child => $books) {
            foreach ($books as $canon => $x) {
                $out[$child][$canon]['r'] = min(1.0, $x['r'] + 0.1 * min(3, max(0, $x['finishes'] - 1)));
            }
        }
        return $out;
    }

    // ---- 2. Content-based ----

    // Feature => weight, before TF-IDF.
    private function features(array $b): array
    {
        $f = [];
        $add = function (string $prefix, ?string $value, float $w) use (&$f) {
            $value = trim(mb_strtolower((string) $value));
            if ($value !== '') {
                $f["$prefix:$value"] = max($f["$prefix:$value"] ?? 0, $w);
            }
        };
        $add('cat', $b['category'] ?? null, 1.0);
        foreach (preg_split('/[^\p{L}\p{N}]+/u', mb_strtolower((string) ($b['topic'] ?? ''))) as $word) {
            if (mb_strlen($word) > 2 && !in_array($word, self::STOPWORDS, true)) {
                $add('word', $word, 0.8);
            }
        }
        foreach (explode(',', (string) ($b['tags'] ?? '')) as $tag) {
            $add('tag', $tag, 0.8);
        }
        $add('level', $b['difficulty'] ?? null, 0.5);
        $add('format', $b['format'] ?? null, 0.4);
        $add('lang', $b['language'] ?? null, 0.6);
        $add('genre', $b['genre'] ?? null, 0.5);
        foreach ($b['emotions'] ?? [] as $e) {
            $add('feel', $e, 0.4);
        }
        return $f;
    }

    private function vectors(array $books): array
    {
        $raw = array_map(fn ($b) => $this->features($b), $books);
        $df = [];
        foreach ($raw as $f) {
            foreach (array_keys($f) as $k) {
                $df[$k] = ($df[$k] ?? 0) + 1;
            }
        }
        $n = count($books);
        return array_map(function ($f) use ($df, $n) {
            $v = [];
            foreach ($f as $k => $w) {
                $v[$k] = $w * (log(($n + 1) / ($df[$k] + 1)) + 1);
            }
            return $v;
        }, $raw);
    }

    // The child's taste: liked books add their features, disliked ones subtract.
    private function profile(array $mine, array $byCanon, array $vectors): ?array
    {
        $p = [];
        foreach ($mine as $canon => $x) {
            if (!isset($byCanon[$canon])) {
                continue;
            }
            $pull = ($x['r'] - self::NEUTRAL) * $x['w'];
            foreach ($vectors[$byCanon[$canon]] as $k => $v) {
                $p[$k] = ($p[$k] ?? 0) + $pull * $v;
            }
        }
        return array_filter($p, fn ($v) => abs($v) > 1e-9) ?: null;
    }

    // Cosine similarity, moved from -1..1 to 0..1.
    private function contentScore(array $profile, array $vector): float
    {
        return 0.5 + 0.5 * self::cosine($profile, $vector);
    }

    public static function cosine(array $a, array $b): float
    {
        $dot = 0.0;
        foreach ($a as $k => $v) {
            if (isset($b[$k])) {
                $dot += $v * $b[$k];
            }
        }
        $na = sqrt(array_sum(array_map(fn ($v) => $v * $v, $a)));
        $nb = sqrt(array_sum(array_map(fn ($v) => $v * $v, $b)));
        return $na > 0 && $nb > 0 ? $dot / ($na * $nb) : 0.0;
    }

    // ---- 3. Collaborative (item-item) ----

    // [canonA][canonB] => similarity, for pairs read by enough of the same children.
    private function itemSimilarity(array $ratings): array
    {
        $byBook = [];
        foreach ($ratings as $child => $books) {
            foreach ($books as $canon => $x) {
                $byBook[$canon][$child] = $x['r'];
            }
        }
        $sim = [];
        $canons = array_keys($byBook);
        foreach ($canons as $i => $a) {
            foreach (array_slice($canons, $i + 1) as $b) {
                $common = array_intersect_key($byBook[$a], $byBook[$b]);
                if (count($common) < self::MIN_CO_READERS) {
                    continue;
                }
                $s = self::cosine(
                    array_map(fn ($r) => $r - self::NEUTRAL, $byBook[$a]),
                    array_map(fn ($r) => $r - self::NEUTRAL, $byBook[$b])
                );
                $sim[$a][$b] = $s;
                $sim[$b][$a] = $s;
            }
        }
        return $sim;
    }

    private function collaborativeScore(string $canon, array $mine, array $sim): ?float
    {
        $num = 0.0;
        $den = 0.0;
        foreach ($mine as $other => $x) {
            if ($other === $canon || !isset($sim[$canon][$other])) {
                continue;
            }
            $s = $sim[$canon][$other];
            $num += $s * ($x['r'] - self::NEUTRAL);
            $den += abs($s);
        }
        return $den > 0 ? 0.5 + 0.5 * max(-1.0, min(1.0, $num / $den / (1 - self::NEUTRAL))) : null;
    }

    // ---- 4. Popularity ----

    private function popularity(array $ratings): array
    {
        $sum = [];
        $count = [];
        $all = 0.0;
        $n = 0;
        foreach ($ratings as $books) {
            foreach ($books as $canon => $x) {
                $sum[$canon] = ($sum[$canon] ?? 0) + $x['r'];
                $count[$canon] = ($count[$canon] ?? 0) + 1;
                $all += $x['r'];
                $n++;
            }
        }
        if ($n === 0) {
            return [];
        }
        $mean = $all / $n;
        $out = [];
        foreach ($sum as $canon => $s) {
            $out[$canon] = ($s + self::PRIOR_COUNT * $mean) / ($count[$canon] + self::PRIOR_COUNT);
        }
        return $out;
    }

    // ---- 5. Context ----

    public function moodFit(array $emotions, ?string $mood): ?float
    {
        $wanted = self::MOOD_EMOTIONS[$mood] ?? null;
        if ($wanted === null || $emotions === []) {
            return null;
        }
        $fits = count(array_intersect($emotions, $wanted));
        $clashes = count(array_intersect($emotions, self::MOOD_CLASHES[$mood] ?? []));
        return max(0.0, min(1.0, min($fits, 3) / 3 - 0.34 * $clashes));
    }

    /* The hardest level the child finishes at least 60% of (2+ books),
       or null with too little to go on. */
    private function comfortLevel(array $mine, array $books, array $byCanon): ?int
    {
        $byLevel = [];
        foreach ($mine as $canon => $x) {
            if (!isset($byCanon[$canon])) {
                continue;
            }
            $level = self::LEVELS[mb_strtolower((string) ($books[$byCanon[$canon]]['difficulty'] ?? ''))] ?? null;
            if ($level !== null) {
                $byLevel[$level][] = $x['r'] >= 0.95 ? 1.0 : 0.0;
            }
        }
        $comfort = null;
        foreach ([0, 1, 2] as $level) {
            $done = $byLevel[$level] ?? [];
            if (count($done) >= 2 && array_sum($done) / count($done) >= 0.6) {
                $comfort = $level;
            }
        }
        return $comfort;
    }

    // Difficulty a little above what they finish is best; and the age group.
    private function fit(array $b, ?int $comfort, ?int $age): ?float
    {
        $parts = [];
        $level = self::LEVELS[mb_strtolower((string) ($b['difficulty'] ?? ''))] ?? null;
        if ($comfort !== null && $level !== null) {
            $parts[] = match ($level - $comfort) {
                0 => 1.0,
                1 => 0.8,   // a little challenge
                -1 => 0.6,
                default => 0.2,
            };
        }
        if ($age !== null && preg_match('/(\d+)\s*-\s*(\d+)/', (string) ($b['age_group'] ?? ''), $m)) {
            $lo = (int) $m[1];
            $hi = (int) $m[2];
            $parts[] = $age >= $lo && $age <= $hi ? 1.0 : max(0.2, 1 - 0.15 * min(abs($age - $lo), abs($age - $hi)));
        }
        return $parts === [] ? null : array_sum($parts) / count($parts);
    }

    // ---- Why ----

    /* A personal reason ("like a book you liked", "others who liked...")
       says more than "popular" or "just right", so it wins when its lift
       is at least PERSONAL_SHARE of the top one. */
    private function reason(array $lift, array $b, array $mine, array $books, array $byCanon, array $vectors, array $sim, array $context): array
    {
        $lift = array_filter($lift, fn ($v) => $v > 1e-6);
        arsort($lift);
        $top = $lift ? reset($lift) : 0.0;
        $order = array_keys($lift);
        $personal = array_values(array_filter($order, fn ($p) => in_array($p, ['content', 'collaborative'], true)
            && $lift[$p] >= self::PERSONAL_SHARE * $top));
        $order = array_values(array_unique([...$personal, ...$order]));
        foreach ($order as $part) {
            switch ($part) {
                case 'content':
                    $like = $this->closestLiked($b, $mine, $byCanon, $vectors, $books);
                    if ($like !== null) {
                        return ['code' => 'like_book', 'params' => ['title' => $like]];
                    }
                    break;
                case 'collaborative':
                    $best = null;
                    $top = 0.0;
                    foreach ($mine as $canon => $x) {
                        $s = $sim[$b['canon']][$canon] ?? 0.0;
                        if ($x['r'] > self::NEUTRAL && $s > $top && isset($byCanon[$canon])) {
                            $top = $s;
                            $best = $books[$byCanon[$canon]]['title'];
                        }
                    }
                    if ($best !== null) {
                        return ['code' => 'others_liked', 'params' => ['title' => $best]];
                    }
                    break;
                case 'mood':
                    return ['code' => 'fits_mood', 'params' => ['mood' => $context['mood']]];
                case 'taste':
                    return ['code' => 'music_taste', 'params' => ['genre' => $b['genre']]];
                case 'fit':
                    return ['code' => 'just_right', 'params' => []];
                case 'popular':
                    return ['code' => 'popular', 'params' => []];
            }
        }
        return ['code' => 'popular', 'params' => []];
    }

    // The liked book most like [b] (by features), other than itself.
    private function closestLiked(array $b, array $mine, array $byCanon, array $vectors, array $books): ?string
    {
        $target = $vectors[array_search($b['id'], array_column($books, 'id'), true)];
        $best = null;
        $top = 0.1;
        foreach ($mine as $canon => $x) {
            if ($canon === $b['canon'] || $x['r'] <= self::NEUTRAL || !isset($byCanon[$canon])) {
                continue;
            }
            $s = self::cosine($target, $vectors[$byCanon[$canon]]);
            if ($s > $top) {
                $top = $s;
                $best = $books[$byCanon[$canon]]['title'];
            }
        }
        return $best;
    }

    // ---- Variety ----

    /* Maximal Marginal Relevance: each next pick balances its score
       against how alike it is to the ones already picked. */
    private function diversify(array $scored, array $vectors, int $limit): array
    {
        $picked = [];
        while (count($picked) < $limit && $scored !== []) {
            $bestKey = null;
            $bestValue = -INF;
            foreach ($scored as $key => $s) {
                $overlap = 0.0;
                foreach ($picked as $p) {
                    $overlap = max($overlap, self::cosine($vectors[$s['index']], $vectors[$p['index']]));
                }
                $value = self::MMR_LAMBDA * $s['score'] - (1 - self::MMR_LAMBDA) * $overlap;
                if ($value > $bestValue) {
                    $bestValue = $value;
                    $bestKey = $key;
                }
            }
            $picked[] = $scored[$bestKey];
            unset($scored[$bestKey]);
        }
        return array_map(fn ($p) => [
            'audiobook_id' => $p['id'],
            'score'        => round($p['score'], 3),
            'parts'        => $p['parts'],
            'reason'       => $p['reason'],
            'new'          => $p['new'],
        ], $picked);
    }
}
