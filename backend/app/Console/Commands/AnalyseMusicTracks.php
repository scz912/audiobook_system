<?php

namespace App\Console\Commands;

use App\Models\MusicTrack;
use App\Services\MusicTagger;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Process;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

/* Has the AI listen to tracks it hasn't heard yet: tracks with no genre,
   and tracks only tagged from their rhythm because the AI couldn't listen
   at upload (no ai_summary). Every track ends with a genre (Others when it
   can't be settled). By default a track keeps its emotion tags; --retag
   replaces them, with the tempo, summary and sensory notes, by the AI's.
   The server runs `music:analyse --retag` in the background at start-up,
   so the whole library is re-listened to once and stays tagged.

     php artisan music:analyse            tracks the AI hasn't heard yet
     php artisan music:analyse --all      every track again
     php artisan music:analyse --retag    ...and redo their emotion tags too */
class AnalyseMusicTracks extends Command
{
    protected $signature = 'music:analyse
        {--all : Also re-analyse tracks that already have a genre}
        {--retag : Replace emotion tags, tempo, summary and sensory notes too}';

    protected $description = 'Measure rhythm and find the genre (and emotion) of music tracks';

    public function handle(MusicTagger $tagger): int
    {
        $hasFfmpeg = $this->ffmpegAvailable();
        if (!$hasFfmpeg) {
            $this->warn('ffmpeg not found: rhythm will not be measured, the AI will judge by ear only.');
        }

        $tracks = MusicTrack::query()
            ->when(!$this->option('all'), fn ($q) => $q->where(
                fn ($w) => $w->whereNull('genre')->orWhereNull('ai_summary'),
            ))
            ->orderBy('created_at')
            ->get();
        if ($tracks->isEmpty()) {
            $this->info('The AI has heard every track. Use --all to analyse them again.');
            return self::SUCCESS;
        }

        $done = 0;
        foreach ($tracks as $track) {
            $path = $this->localPath($track->file_path);
            if ($path === null) {
                $this->warn("Skipped \"{$track->title}\": its file isn't on this server.");
                continue;
            }

            ['measured' => $measured, 'analysis' => $analysis] = $tagger->tag(
                $path,
                $track->title,
                MusicTrack::emotionVocabulary($track->caregiver_id)->all(),
                $hasFfmpeg,
            );
            $fromAi = $analysis['source'] === 'ai';
            if (!$fromAi && $track->genre !== null) {
                // The AI still can't listen; keep the labels it has and try
                // again on the next run.
                $this->warn("\"{$track->title}\": the AI couldn't listen; kept its labels for now.");
                continue;
            }

            // Fresh emotions when asked, or when the track has none yet.
            $retag = $this->option('retag') || !$track->tagsArray();
            $track->fill(array_filter([
                'genre'         => $analysis['genre'],
                'bpm'           => $measured['bpm'] ?? null,
                'beat'          => $measured['beat'] ?? null,
                'tags'          => $retag && $analysis['tags'] ? implode(',', $analysis['tags']) : null,
                'tempo'         => ($retag || !$track->tempo) ? $analysis['tempo'] : null,
                // Left empty when the AI didn't listen, so the next run retries.
                'ai_summary'    => $fromAi && ($retag || !$track->ai_summary) ? ($analysis['summary'] ?: null) : null,
                'sensory_notes' => ($retag || !$track->sensory_notes) ? ($analysis['sensory_notes'] ?: null) : null,
            ], fn ($v) => $v !== null));
            if ($measured !== null && $measured['bpm'] === null) {
                // No pulse to follow: clear any old tempo number.
                $track->bpm = null;
            }
            $track->save();
            $done++;

            $rhythm = $measured === null ? 'not measured'
                : ($measured['bpm'] ? "{$measured['bpm']} BPM, {$measured['beat']} pulse" : 'no clear pulse');
            $this->line(sprintf(
                '%-40s %-11s %s | %s',
                Str::limit($track->title, 38),
                $track->genre ?? '-',
                $rhythm,
                implode(', ', $track->tagsArray()),
            ));
        }

        $this->info("Analysed {$done} of {$tracks->count()} tracks.");
        return self::SUCCESS;
    }

    // "storage/bgm/x.mp3" -> the file on disk; null for links or missing files.
    private function localPath(?string $filePath): ?string
    {
        if (!$filePath || Str::startsWith($filePath, ['http://', 'https://'])) {
            return null;
        }
        $path = Storage::disk('public')->path(Str::after($filePath, 'storage/'));
        return is_file($path) ? $path : null;
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
