<?php

namespace App\Console\Commands;

use App\Models\MusicTrack;
use App\Services\MusicTagger;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Process;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

/* Gives tracks already in the library a genre and a measured rhythm (new
   uploads get them as they arrive). By default it only fills what's
   missing: the built-in tracks keep their hand-picked emotion tags, and
   so do uploads. --retag also replaces the emotion tags, tempo, summary
   and sensory notes with fresh AI ones.

     php artisan music:analyse            tracks with no genre yet
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
            ->when(!$this->option('all'), fn ($q) => $q->whereNull('genre'))
            ->orderBy('created_at')
            ->get();
        if ($tracks->isEmpty()) {
            $this->info('Every track already has a genre. Use --all to analyse them again.');
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
            if ($measured === null && $analysis === null) {
                $this->warn("Skipped \"{$track->title}\": couldn't measure or listen to it.");
                continue;
            }

            $retag = $this->option('retag') && $analysis !== null && $analysis['tags'];
            $track->fill(array_filter([
                'genre'         => $analysis['genre'] ?? null,
                'bpm'           => $measured['bpm'] ?? null,
                'beat'          => $measured['beat'] ?? null,
                'tags'          => $retag ? implode(',', $analysis['tags']) : null,
                'tempo'         => ($retag || !$track->tempo) ? ($analysis['tempo'] ?? null) : null,
                'ai_summary'    => ($retag || !$track->ai_summary) ? (($analysis['summary'] ?? '') ?: null) : null,
                'sensory_notes' => $retag ? (($analysis['sensory_notes'] ?? '') ?: null) : null,
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
