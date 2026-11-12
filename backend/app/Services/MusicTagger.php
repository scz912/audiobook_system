<?php

namespace App\Services;

use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Process;
use Illuminate\Support\Str;

/* Works out a music track's genre and emotion: measures its rhythm from
   the audio (AudioRhythmAnalyzer), then has Gemini listen to it with those
   measurements in hand (GeminiService::analyseMusic). Used for caregiver
   uploads and by `php artisan music:analyse` for tracks already in the
   library. */
class MusicTagger
{
    /* Gemini takes at most ~20 MB per request and base64 adds a third, so
       send files up to this size whole. Bigger ones need ffmpeg to make a
       smaller listening copy. */
    private const MAX_INLINE_AI_BYTES = 14 * 1024 * 1024;

    public function __construct(
        private GeminiService $gemini,
        private AudioRhythmAnalyzer $rhythm,
    ) {}

    /* ['measured' => rhythm numbers or null, 'analysis' => Gemini's genre,
       tags, tempo, summary and sensory notes, or null]. Either can be null
       (no ffmpeg, no Gemini key, a failed call); the caller keeps the track
       either way. [vocabulary] is the emotion tags already in use. */
    public function tag(string $mp3Path, string $title, array $vocabulary, bool $hasFfmpeg): array
    {
        $measured = $hasFfmpeg ? $this->rhythm->analyseFile($mp3Path) : null;

        $analysis = null;
        if ($this->gemini->isConfigured()) {
            [$bytes, $cleanup, $mime] = $this->audioForAnalysis($mp3Path, $hasFfmpeg);
            if ($bytes !== null) {
                // Two listens: a genre is kept only when they agree.
                $analysis = $this->gemini->analyseMusicTwice($bytes, $mime, $title, $vocabulary, $measured);
            }
            if ($cleanup) {
                @unlink($cleanup);
            }
        }

        return ['measured' => $measured, 'analysis' => $analysis];
    }

    // What Gemini is told the audio is, by file type (uploads are always mp3).
    private const MIME_BY_EXTENSION = [
        'mp3' => 'audio/mp3', 'ogg' => 'audio/ogg', 'oga' => 'audio/ogg', 'opus' => 'audio/ogg',
        'wav' => 'audio/wav', 'flac' => 'audio/flac', 'm4a' => 'audio/aac', 'aac' => 'audio/aac',
    ];

    /* [bytes, temp file to delete afterwards, mime type] to send to Gemini. With
       ffmpeg we send a small mono copy of the first 6 minutes (plenty to
       judge the mood and flow, and well under Gemini's size limit). Without
       it we send the mp3 whole if it's small enough, else skip the AI. */
    private function audioForAnalysis(string $mp3Path, bool $hasFfmpeg): array
    {
        if ($hasFfmpeg) {
            $clip = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'bgm-' . Str::uuid() . '.mp3';
            try {
                $result = Process::timeout(120)->run([
                    config('services.ffmpeg.path'), '-y', '-i', $mp3Path,
                    '-t', '360', '-ac', '1', '-ar', '22050',
                    '-codec:a', 'libmp3lame', '-b:a', '64k',
                    $clip,
                ]);
                if ($result->successful() && is_file($clip) && filesize($clip) > 0) {
                    return [file_get_contents($clip), $clip, 'audio/mp3'];
                }
            } catch (\Throwable $e) {
                Log::warning('[MusicTagger] analysis clip failed', ['error' => $e->getMessage()]);
            }
            @unlink($clip);
        }

        if (filesize($mp3Path) <= self::MAX_INLINE_AI_BYTES) {
            $ext = strtolower(pathinfo($mp3Path, PATHINFO_EXTENSION));
            return [file_get_contents($mp3Path), null, self::MIME_BY_EXTENSION[$ext] ?? 'audio/mp3'];
        }
        Log::warning('[MusicTagger] file too large to analyse without ffmpeg', [
            'bytes' => filesize($mp3Path),
        ]);
        return [null, null, null];
    }
}
