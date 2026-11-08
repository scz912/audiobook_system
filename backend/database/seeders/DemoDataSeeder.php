<?php

namespace Database\Seeders;

use App\Models\AiSuggestion;
use App\Models\Audiobook;
use App\Models\Caregiver;
use App\Models\ChildProfile;
use App\Models\ChildSettings;
use Carbon\Carbon;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/* Fills one caregiver account with demo children, settings, listening
   history and AI suggestions so the caregiver screens (profiles, insights,
   suggestions) have something realistic to show while working on the UI.

   Run:  DEMO_EMAIL=you@example.com php artisan db:seed --class=DemoDataSeeder

   Safe to re-run: it first deletes the demo children it created before
   (matched by name on that caregiver), then recreates them. Real children
   on the account are never touched. Set DEMO_WIPE=1 to only remove the
   demo children without adding them back. */
class DemoDataSeeder extends Seeder
{
    private const TZ = 'Asia/Kuala_Lumpur';

    /* Each child has a different listening pattern so every insights
       state shows up: a long streak, a curious skipper, a sleepy toddler
       who drops off early, and a brand-new child (low confidence). */
    private function children(): array
    {
        return [
            [
                'name' => 'Aisyah', 'age' => 7, 'emoji' => '🌸', 'color' => '#F5D5DD',
                'genre' => 'Fantasy',
                'days' => 30, 'skip_chance' => 0.0, 'streak' => 12, 'per_day' => [1, 2],
                'hours' => [16, 17, 20], 'complete' => 0.85, 'pauses' => [0, 2], 'skips' => [0, 1],
                'moods' => ['happy' => 6, 'calm' => 3, 'curious' => 2, 'sleepy' => 1],
                'settings' => ['narrator_voice' => 'gentle_female', 'reading_speed' => 1.00,
                    'volume' => 0.80, 'text_scale' => 1.10, 'reduced_animations' => false,
                    'auto_play_next' => true, 'read_along' => true],
            ],
            [
                'name' => 'Daniel', 'age' => 9, 'emoji' => '🚀', 'color' => '#DDE7F2',
                'genre' => 'Science',
                'days' => 30, 'skip_chance' => 0.35, 'streak' => 4, 'per_day' => [1, 2],
                'hours' => [15, 16, 18], 'complete' => 0.55, 'pauses' => [1, 3], 'skips' => [1, 4],
                'moods' => ['curious' => 6, 'happy' => 3, 'calm' => 1, 'sleepy' => 0],
                'settings' => ['narrator_voice' => 'warm_male', 'reading_speed' => 1.25,
                    'volume' => 0.70, 'text_scale' => 1.00, 'reduced_animations' => true,
                    'auto_play_next' => true, 'read_along' => false],
            ],
            [
                'name' => 'Mei Ling', 'age' => 4, 'emoji' => '🐢', 'color' => '#C8E4D2',
                'genre' => 'Bedtime',
                'days' => 28, 'skip_chance' => 0.3, 'streak' => 0, 'per_day' => [1, 1],
                'hours' => [20, 21], 'complete' => 0.30, 'pauses' => [2, 5], 'skips' => [0, 2],
                'early_drop' => 0.6,
                'moods' => ['sleepy' => 6, 'calm' => 4, 'happy' => 1, 'curious' => 0],
                'settings' => ['narrator_voice' => 'calm_female', 'reading_speed' => 1.10,
                    'volume' => 0.90, 'text_scale' => 1.00, 'reduced_animations' => false,
                    'auto_play_next' => true, 'read_along' => true],
            ],
            [
                'name' => 'Arjun', 'age' => 5, 'emoji' => '🦁', 'color' => '#F5E3D0',
                'genre' => 'Animals',
                // Only a few sessions -> confidence "low" on the suggestion card.
                'fixed_days' => [0, 1, 3], 'per_day' => [1, 1],
                'hours' => [10, 17], 'complete' => 0.67, 'pauses' => [0, 2], 'skips' => [0, 1],
                'moods' => ['happy' => 2, 'curious' => 1, 'calm' => 0, 'sleepy' => 0],
                'settings' => ['narrator_voice' => 'friendly_child', 'reading_speed' => 1.00,
                    'volume' => 0.80, 'text_scale' => 1.00, 'reduced_animations' => true,
                    'auto_play_next' => false, 'read_along' => true],
            ],
        ];
    }

    /* Hand-written tips per child, in the same shape InsightsController
       saves from Gemini. Mixed statuses so every card state is visible. */
    private function suggestionsFor(string $name): array
    {
        return match ($name) {
            'Aisyah' => [
                'stale' => false,
                'items' => [
                    ['text_scale', 1.25, 'Aisyah finishes most stories and follows the read-along closely. Slightly larger text may make it even easier to track words as she reads.', 'pending'],
                    ['reading_speed', 1.10, 'She completes 85% of sessions with very few pauses, so a slightly quicker pace should still feel comfortable.', 'accepted'],
                ],
            ],
            'Daniel' => [
                'stale' => false,
                'items' => [
                    ['reading_speed', 1.00, 'Daniel skips ahead often and finishes about half his stories. A calmer pace may help him stay with the story instead of jumping forward.', 'pending'],
                    ['read_along', true, 'Turning on read-along highlights each word as it is spoken, which can give curious listeners something to focus on and reduce skipping.', 'pending'],
                    ['volume', 0.85, 'Short sessions with frequent pauses can mean the narration is hard to hear over background noise.', 'dismissed'],
                ],
            ],
            'Mei Ling' => [
                // Pretend the last Gemini call failed so the "stale" banner shows.
                'stale' => true,
                'items' => [
                    ['reading_speed', 0.85, 'Mei Ling often stops before the halfway point and pauses a lot. A slower, gentler pace suits bedtime listening for a 4-year-old.', 'pending'],
                    ['reduced_animations', true, 'Most of her sessions happen late in the evening with a sleepy mood. Fewer animations can make the screen calmer before sleep.', 'pending'],
                    ['volume', 0.70, 'A softer volume is usually more soothing at bedtime and may help her settle into the story.', 'edited'],
                    ['auto_play_next', false, 'Stopping after one story helps keep bedtime routines predictable.', 'pending'],
                ],
            ],
            'Arjun' => [
                'stale' => false,
                'items' => [
                    ['auto_play_next', true, 'Arjun has only a few sessions so far, but he finishes most of them. Auto-playing the next story may help him discover more he enjoys.', 'pending'],
                ],
            ],
            default => ['stale' => false, 'items' => []],
        };
    }

    public function run(): void
    {
        $email = env('DEMO_EMAIL', 'frost6x2x9@gmail.com');
        $caregiver = Caregiver::where('email', $email)->first();
        if (!$caregiver) {
            $this->command?->error("No caregiver with email {$email}. Register in the app first.");
            return;
        }

        $demoNames = array_column($this->children(), 'name');

        DB::transaction(function () use ($caregiver, $demoNames) {
            // Cascades remove their history, settings and suggestions.
            $removed = $caregiver->childProfiles()->whereIn('name', $demoNames)->get();
            foreach ($removed as $p) {
                $p->delete();
            }
            $this->command?->info("Removed {$removed->count()} previous demo children.");
        });

        if (env('DEMO_WIPE')) {
            return;
        }

        $books = Audiobook::visibleTo($caregiver->caregiver_id)
            ->where('status', 'available')
            ->get(['audiobook_id', 'title', 'duration_minutes']);
        if ($books->isEmpty()) {
            $this->command?->error('No audiobooks visible to this caregiver; history needs at least one.');
            return;
        }
        $this->command?->info("Using {$books->count()} audiobooks for listening history.");

        // Same numbers on every run, so screenshots stay comparable.
        mt_srand(20261108);

        DB::transaction(function () use ($caregiver, $books) {
            $now = Carbon::now(self::TZ);
            foreach ($this->children() as $i => $c) {
                $profile = ChildProfile::create([
                    'caregiver_id'   => $caregiver->caregiver_id,
                    'name'           => $c['name'],
                    'age'            => $c['age'],
                    'avatar_emoji'   => $c['emoji'],
                    'avatar_color'   => $c['color'],
                    'favorite_genre' => $c['genre'],
                ]);
                // Keep the order of the selector stable (it sorts by created_at).
                $profile->created_at = $now->copy()->subDays(60 - $i)->utc();
                $profile->save();

                ChildSettings::create(['child_id' => $profile->child_id] + $c['settings']);

                $rows = $this->historyRows($profile->child_id, $c, $books, $now);
                foreach (array_chunk($rows, 200) as $chunk) {
                    DB::table('listening_history')->insert($chunk);
                }
                $minutes = array_sum(array_map(
                    fn ($r) => (int) round($r['duration_seconds'] / 60), $rows));
                $profile->listening_minutes = $minutes;
                $profile->save();

                $this->createSuggestion($profile, $c, $rows, $now);

                $this->command?->info(sprintf('  %s: %d sessions, %d min',
                    $c['name'], count($rows), $minutes));
            }
        });
    }

    /* Build the listening sessions for one child, as raw rows. */
    private function historyRows(string $childId, array $c, $books, Carbon $now): array
    {
        // Which days (counted back from today) the child listened.
        if (isset($c['fixed_days'])) {
            $days = $c['fixed_days'];
        } else {
            $days = [];
            for ($d = 0; $d < $c['days']; $d++) {
                $inStreak = $c['streak'] > 0 && $d < $c['streak'];
                // streak = 0 means "missed today and yesterday" so the streak reads 0.
                if ($c['streak'] === 0 && $d < 2) {
                    continue;
                }
                if ($inStreak || $this->chance(1 - $c['skip_chance'])) {
                    $days[] = $d;
                }
            }
            // Break the streak right after it so the number shown is exact.
            if ($c['streak'] > 0) {
                $days = array_values(array_diff($days, [$c['streak']]));
            }
        }

        $moodPool = [];
        foreach ($c['moods'] as $mood => $weight) {
            for ($w = 0; $w < $weight; $w++) {
                $moodPool[] = $mood;
            }
        }
        $all = $books->values()->all();
        $favourites = $all;
        for ($k = count($favourites) - 1; $k > 0; $k--) {
            $j = mt_rand(0, $k);
            [$favourites[$k], $favourites[$j]] = [$favourites[$j], $favourites[$k]];
        }
        $favourites = array_slice($favourites, 0, min(4, count($favourites)));

        $rows = [];
        foreach ($days as $d) {
            $count = mt_rand($c['per_day'][0], $c['per_day'][1]);
            for ($n = 0; $n < $count; $n++) {
                // Mostly re-listen to favourites, sometimes try something new.
                $pool = $this->chance(0.7) ? $favourites : $all;
                $book = $pool[mt_rand(0, count($pool) - 1)];
                $bookSeconds = max(3, (int) ($book->duration_minutes ?: mt_rand(6, 15))) * 60;

                $completed = $this->chance($c['complete']);
                if ($completed) {
                    $duration = $bookSeconds + mt_rand(-30, 60);
                    $position = $bookSeconds;
                } else {
                    $frac = $this->chance($c['early_drop'] ?? 0.4)
                        ? mt_rand(10, 45) / 100
                        : mt_rand(55, 90) / 100;
                    $position = (int) ($bookSeconds * $frac);
                    $duration = $position + mt_rand(0, 40);
                }
                $duration = max(30, $duration);

                $hour = $c['hours'][array_rand($c['hours'])];
                $at = $now->copy()->subDays($d)->setTime($hour, mt_rand(0, 59), mt_rand(0, 59));
                if ($at->greaterThan($now)) {
                    $at = $now->copy()->subMinutes(mt_rand(20, 90) + $n * 30);
                }
                $at = $at->utc()->format('Y-m-d H:i:s');

                $rows[] = [
                    'history_id'            => (string) Str::uuid(),
                    'child_id'              => $childId,
                    'audiobook_id'          => $book->audiobook_id,
                    'duration_seconds'      => $duration,
                    'last_position_seconds' => $position,
                    // A few sessions without a mood, like real usage.
                    'mood'                  => $this->chance(0.9) ? $moodPool[array_rand($moodPool)] : null,
                    'completed'             => $completed,
                    'pause_count'           => mt_rand($c['pauses'][0], $c['pauses'][1]),
                    'skip_count'            => mt_rand($c['skips'][0], $c['skips'][1]),
                    'created_at'            => $at,
                    'updated_at'            => $at,
                ];
            }
        }
        return $rows;
    }

    private function createSuggestion(ChildProfile $profile, array $c, array $rows, Carbon $now): void
    {
        $spec = $this->suggestionsFor($c['name']);
        if (empty($spec['items'])) {
            return;
        }
        $settings = $c['settings'];
        $items = [];
        foreach ($spec['items'] as [$key, $suggested, $reason, $status]) {
            $item = [
                'id'              => (string) Str::uuid(),
                'setting_key'     => $key,
                'current_value'   => $settings[$key],
                'suggested_value' => $suggested,
                'reason'          => $reason,
                'status'          => $status,
            ];
            if ($status === 'accepted' || $status === 'edited') {
                $applied = $status === 'edited' ? 0.75 : $suggested;
                $item['applied_value'] = $applied;
                // Applied tips change the real settings, like the API does.
                $profile->childSettings()->update([$key => $applied]);
            }
            $items[] = $item;
        }

        AiSuggestion::create([
            'child_id'     => $profile->child_id,
            'source_stats' => $this->stats($rows, $settings),
            'items'        => $items,
            'confidence'   => count($rows) < 5 ? 'low' : 'normal',
            'is_stale'     => $spec['stale'],
            'generated_at' => $now->copy()->subHours($spec['stale'] ? 52 : 3)->utc(),
        ]);
    }

    /* Same stats InsightsController::aggregateStatsFor sends Gemini. */
    private function stats(array $rows, array $settings): array
    {
        $since = Carbon::now()->subDays(30)->format('Y-m-d H:i:s');
        $rows = array_values(array_filter($rows, fn ($r) => $r['created_at'] >= $since));
        $count = count($rows);
        $moods = ['happy' => 0, 'calm' => 0, 'curious' => 0, 'sleepy' => 0];
        $secs = $done = $pauses = $skips = $early = 0;
        foreach ($rows as $r) {
            $secs += $r['duration_seconds'];
            $pauses += $r['pause_count'];
            $skips += $r['skip_count'];
            if ($r['completed']) {
                $done++;
            } elseif ($r['duration_seconds'] > 0
                && $r['last_position_seconds'] / $r['duration_seconds'] < 0.5) {
                $early++;
            }
            if ($r['mood']) {
                $moods[$r['mood']]++;
            }
        }
        return [
            'window_days'         => 30,
            'sessions_count'      => $count,
            'avg_session_minutes' => $count ? round($secs / $count / 60, 1) : 0.0,
            'completion_rate'     => $count ? round($done / $count, 3) : 0.0,
            'early_drop_rate'     => $count ? round($early / $count, 3) : 0.0,
            'pause_rate'          => $count ? round($pauses / $count, 2) : 0.0,
            'skip_rate'           => $count ? round($skips / $count, 2) : 0.0,
            'mood_breakdown'      => $moods,
            'current_settings'    => $settings,
        ];
    }

    private function chance(float $p): bool
    {
        return mt_rand() / mt_getrandmax() < $p;
    }
}
