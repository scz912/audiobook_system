<?php

namespace App\Console\Commands;

use App\Models\MusicTrack;
use App\Services\GeminiService;
use App\Services\MusicTagger;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Process;
use Illuminate\Support\Str;

/* Measures how often the genre and emotion tagging is right, on music
   whose answers are already known.

   Each folder holds audio files and a labels.csv:

       file,genre,emotions,note
       rain.ogg,Nature,Calm;Peaceful,from Commons "Sounds of rain"

   genre is one of GeminiService::MUSIC_GENRES, or blank to score only the
   emotions; emotions (optional) are ;-separated. Every track is run through exactly what an upload does
   (rhythm measured, then Gemini listens) and the answers are compared:

   - genre: right or wrong, per genre, and which genres get mixed up;
   - emotions (where labelled): how many of the expected emotions the AI
     gave, and how many of its emotions were expected;
   - --runs=2 tags each track twice to see how often it changes its mind.

   The full results go to [folder]/report.json (the last folder given).

     php artisan music:evaluate storage/app/private/music-eval/commons
     php artisan music:evaluate folderA folderB --runs=2 --delay=7 */
class EvaluateMusicTagging extends Command
{
    protected $signature = 'music:evaluate
        {folders* : Folders, each with audio files and a labels.csv}
        {--runs=1 : Tag each track this many times (2+ checks consistency)}
        {--delay=6 : Seconds to wait between AI calls (stays under rate limits)}
        {--limit=0 : Only the first N tracks of each folder (0 = all)}
        {--titles : Tell the AI each file name as the title (off: it judges by ear alone)}';

    protected $description = 'Test genre and emotion tagging against music with known answers';

    // The emotion words a new upload is offered when there's no library to read.
    private const DEFAULT_EMOTIONS = [
        'Adventurous', 'Calm', 'Curious', 'Energetic', 'Gentle', 'Happy', 'Imaginative',
        'Mysterious', 'Peaceful', 'Playful', 'Relaxing', 'Soothing', 'Upbeat', 'Whimsical',
    ];

    public function handle(MusicTagger $tagger, GeminiService $gemini): int
    {
        if (!$gemini->isConfigured()) {
            $this->error('No GEMINI_API_KEY is set, so genre and emotion cannot be tested.');
            return self::FAILURE;
        }
        $hasFfmpeg = $this->ffmpegAvailable();
        if (!$hasFfmpeg) {
            $this->warn('ffmpeg not found: rhythm will not be measured (the AI judges by ear only).');
        }
        $vocabulary = $this->vocabulary();
        $runs = max(1, (int) $this->option('runs'));
        $delay = max(0, (int) $this->option('delay'));

        $tracks = [];
        foreach ($this->argument('folders') as $folder) {
            $loaded = $this->loadLabels($folder);
            if ($loaded === null) {
                return self::FAILURE;
            }
            $limit = (int) $this->option('limit');
            $tracks = array_merge($tracks, $limit > 0 ? array_slice($loaded, 0, $limit) : $loaded);
        }
        if (!$tracks) {
            $this->error('No labelled tracks found.');
            return self::FAILURE;
        }
        $this->info(sprintf('Testing %d tracks x %d run(s)...', count($tracks), $runs));

        $results = [];
        $first = true;
        foreach ($tracks as $i => $t) {
            $answers = [];
            for ($r = 0; $r < $runs; $r++) {
                if (!$first && $delay) {
                    sleep($delay);
                }
                $first = false;
                /* File names often give the answer away ("Rain_and_thunder"),
                   so by default the AI gets a neutral title and must listen. */
                $title = $this->option('titles') ? $t['title'] : 'Untitled track';
                ['measured' => $measured, 'analysis' => $analysis] =
                    $tagger->tag($t['path'], $title, $vocabulary, $hasFfmpeg);
                $answers[] = [
                    'genre'    => $analysis['genre'] ?? null,
                    // What each of the two listens said (genre is kept only
                    // when they agree).
                    'votes'    => $analysis['genre_votes'] ?? [],
                    'emotions' => $analysis['tags'] ?? [],
                    'tempo'    => $analysis['tempo'] ?? null,
                    'summary'  => $analysis['summary'] ?? null,
                    'failed'   => $analysis === null,
                    'rhythm'   => $measured,
                ];
            }
            $main = $answers[0];
            // The listens disagreed, so no genre was given (not counted as wrong).
            $unsure = !$main['failed'] && $main['genre'] === null && count(array_filter($main['votes'])) > 0;
            $row = $t + [
                'answers'       => $answers,
                'genre_unsure'  => $t['genre'] !== null && $unsure,
                'genre_right'   => $t['genre'] === null || $unsure ? null : (!$main['failed'] && $main['genre'] === $t['genre']),
                'first_listen_right' => $t['genre'] === null || $main['failed'] ? null
                    : (($main['votes'][0] ?? $main['genre']) === $t['genre']),
                'emotion_found' => $this->share($t['emotions'], $main['emotions']),
                'emotion_kept'  => $this->share($main['emotions'], $t['emotions']),
            ];
            unset($row['path']);
            $results[] = $row;

            $rhythm = $main['rhythm']
                ? ($main['rhythm']['bpm'] ? $main['rhythm']['bpm'] . ' BPM ' . $main['rhythm']['beat'] : 'no pulse')
                : '-';
            $this->line(sprintf(
                '%3d %s %-34s want %-21s got %-21s %-16s %s',
                $i + 1,
                $main['failed'] ? '!' : ($row['genre_unsure'] ? '?' : ($row['genre_right'] === null ? ' ' : ($row['genre_right'] ? '+' : 'x'))),
                Str::limit($t['file'], 32),
                $t['genre'] ?? '-',
                $main['failed'] ? '(AI failed)'
                    : ($main['genre'] ?? ('unsure: ' . implode('/', array_map(fn ($v) => $v ?? '-', $main['votes'])))),
                $rhythm,
                implode(', ', $main['emotions']),
            ));
        }

        $report = $this->summarise($results, $runs);
        $folders = $this->argument('folders');
        $out = rtrim(end($folders), '/\\') . DIRECTORY_SEPARATOR . 'report.json';
        file_put_contents($out, json_encode(
            [
                'summary' => $report,
                'model'   => config('services.gemini.text_model'),
                'titles'  => (bool) $this->option('titles'),
                'rhythm'  => $hasFfmpeg,
                'tracks'  => $results,
            ],
            JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES,
        ));
        $this->newLine();
        $this->info("Full results: {$out}");
        return self::SUCCESS;
    }

    // Share of [want] found in [got] (case-blind); null if nothing was wanted.
    private function share(array $want, array $got): ?float
    {
        if (!$want) {
            return null;
        }
        $got = array_map('strtolower', $got);
        $hits = count(array_filter($want, fn ($w) => in_array(strtolower($w), $got, true)));
        return $hits / count($want);
    }

    private function summarise(array $results, int $runs): array
    {
        $answered = array_values(array_filter($results, fn ($r) => !$r['answers'][0]['failed']));
        // Genre is scored only on tracks whose genre is known.
        $genred = array_values(array_filter($answered, fn ($r) => $r['genre'] !== null));
        $n = count($genred);
        $unsure = count(array_filter($genred, fn ($r) => $r['genre_unsure']));
        $shown = $n - $unsure;
        $right = count(array_filter($genred, fn ($r) => $r['genre_right']));
        $firstRight = count(array_filter($genred, fn ($r) => $r['first_listen_right']));

        $this->newLine();
        $pct = fn ($a, $b) => $b ? round(100 * $a / $b) . '%' : '-';
        $this->info(sprintf(
            'Genre, one listen: %d of %d right (%s)%s',
            $firstRight, $n, $pct($firstRight, $n),
            count($results) > count($answered) ? sprintf('; %d not answered by the AI', count($results) - count($answered)) : '',
        ));
        $this->info(sprintf(
            'Genre, two listens that agree: shown on %d of %d tracks; %d of those %d right (%s); %d left blank as unsure',
            $shown, $n, $right, $shown, $pct($right, $shown), $unsure,
        ));

        // Per genre, and which genre each miss went to.
        $perGenre = [];
        $mixups = [];
        foreach ($genred as $r) {
            $g = $r['genre'];
            $perGenre[$g] ??= ['right' => 0, 'unsure' => 0, 'total' => 0];
            $perGenre[$g]['total']++;
            if ($r['genre_unsure']) {
                $perGenre[$g]['unsure']++;
            } elseif ($r['genre_right']) {
                $perGenre[$g]['right']++;
            } else {
                $key = $g . ' -> ' . ($r['answers'][0]['genre'] ?? 'none');
                $mixups[$key] = ($mixups[$key] ?? 0) + 1;
            }
        }
        ksort($perGenre);
        arsort($mixups);
        if ($perGenre) $this->table(
            ['Genre', 'Right', 'Wrong', 'Unsure', 'Of'],
            array_map(
                fn ($g, $s) => [$g, $s['right'], $s['total'] - $s['right'] - $s['unsure'], $s['unsure'], $s['total']],
                array_keys($perGenre), $perGenre,
            ),
        );
        if ($mixups) {
            $this->line('Mix-ups (expected -> given): ' . implode(', ', array_map(
                fn ($k, $v) => "{$k} x{$v}", array_keys($mixups), $mixups,
            )));
        }

        // Emotions, only where people labelled them.
        $labelled = array_values(array_filter($answered, fn ($r) => $r['emotion_found'] !== null));
        $emotion = null;
        if ($labelled) {
            $found = array_sum(array_column($labelled, 'emotion_found')) / count($labelled);
            $kept = array_sum(array_column($labelled, 'emotion_kept')) / count($labelled);
            $anyHit = count(array_filter($labelled, fn ($r) => $r['emotion_found'] > 0));
            $emotion = [
                'tracks'          => count($labelled),
                'expected_found'  => round($found, 2),
                'given_expected'  => round($kept, 2),
                'at_least_one'    => $anyHit,
            ];
            $this->info(sprintf(
                'Emotions (%d labelled tracks): found %d%% of the expected emotions; %d%% of the AI\'s emotions were expected; at least one match on %d of %d.',
                count($labelled), round(100 * $found), round(100 * $kept), $anyHit, count($labelled),
            ));
        } else {
            $this->line('Emotions: no labelled emotions, so not scored (see report.json for what the AI gave).');
        }

        // Consistency: same genre every run? How alike were the emotions?
        $consistency = null;
        if ($runs > 1 && $answered) {
            $sameGenre = 0;
            $overlap = 0.0;
            foreach ($answered as $r) {
                $genres = array_unique(array_column($r['answers'], 'genre'));
                $sameGenre += count($genres) === 1 ? 1 : 0;
                $a = array_map('strtolower', $r['answers'][0]['emotions']);
                $b = array_map('strtolower', $r['answers'][1]['emotions']);
                $union = array_unique(array_merge($a, $b));
                $overlap += $union ? count(array_intersect($a, $b)) / count($union) : 1;
            }
            $consistency = [
                'same_genre_every_run' => $sameGenre,
                'emotion_overlap'      => round($overlap / count($answered), 2),
            ];
            $this->info(sprintf(
                'Consistency over %d runs: same genre on %d of %d tracks; emotion tags %d%% the same between runs.',
                $runs, $sameGenre, count($answered), round(100 * $overlap / count($answered)),
            ));
        }

        return [
            'tracks'              => count($results),
            'labelled_answered'   => $n,
            'first_listen_right'  => $firstRight,
            'genre_shown'         => $shown,
            'genre_unsure'        => $unsure,
            'genre_right'         => $right,
            'genre_percent_shown' => $shown ? round(100 * $right / $shown) : null,
            'per_genre'     => $perGenre,
            'mixups'        => $mixups,
            'emotions'      => $emotion,
            'consistency'   => $consistency,
        ];
    }

    /* labels.csv rows that point at real files, with a known genre. Null
       (after saying why) if the folder or its labels can't be used. */
    private function loadLabels(string $folder): ?array
    {
        $csv = rtrim($folder, '/\\') . DIRECTORY_SEPARATOR . 'labels.csv';
        if (!is_file($csv)) {
            $this->error("No labels.csv in {$folder}");
            return null;
        }
        $rows = array_map('str_getcsv', array_filter(array_map('trim', file($csv))));
        $head = array_map(fn ($h) => strtolower(trim($h)), array_shift($rows) ?? []);
        $tracks = [];
        foreach ($rows as $n => $cols) {
            $row = array_combine($head, array_pad(array_slice($cols, 0, count($head)), count($head), ''));
            $file = trim($row['file'] ?? '');
            // Older single genres (Classical, Folk...) count as the merged genre.
            $genre = GeminiService::canonicalGenre($row['genre'] ?? '');
            $path = rtrim($folder, '/\\') . DIRECTORY_SEPARATOR . $file;
            if ($file === '' || !is_file($path)) {
                $this->warn("labels.csv line " . ($n + 2) . ": file \"{$file}\" not found, skipped.");
                continue;
            }
            if ($genre === null && trim($row['genre'] ?? '') !== '') {
                $this->warn("labels.csv line " . ($n + 2) . ": genre \"{$row['genre']}\" is not one of the app's genres, skipped.");
                continue;
            }
            $tracks[] = [
                'file'     => $file,
                'path'     => $path,
                'title'    => Str::title(trim(preg_replace('/[\s_\-]+/', ' ', pathinfo($file, PATHINFO_FILENAME)))),
                'genre'    => $genre,
                'emotions' => array_values(array_filter(array_map('trim', explode(';', $row['emotions'] ?? '')))),
                'note'     => $row['note'] ?? '',
            ];
        }
        return $tracks;
    }


    // The library's emotion words, or the built-in set when there's no database.
    private function vocabulary(): array
    {
        try {
            $words = MusicTrack::emotionVocabulary(null)->all();
            if ($words) {
                return $words;
            }
        } catch (\Throwable $e) {
            // No database here: fall back to the built-in words.
        }
        return self::DEFAULT_EMOTIONS;
    }

    private function ffmpegAvailable(): bool
    {
        try {
            return Process::timeout(10)->run([config('services.ffmpeg.path'), '-version'])->successful();
        } catch (\Throwable $e) {
            return false;
        }
    }
}
