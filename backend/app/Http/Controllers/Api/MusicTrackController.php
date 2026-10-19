<?php

namespace App\Http\Controllers\Api;

use App\Models\MusicTrack;
use App\Services\GeminiService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Process;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class MusicTrackController extends ApiController
{
    // File types we accept. mp3 is stored as-is; the rest need ffmpeg to become mp3.
    private const UPLOAD_EXTENSIONS = ['mp3', 'mp4', 'm4a', 'aac', 'wav', 'ogg', 'flac', 'webm'];

    // Mime types (sniffed from the file bytes, not the name) that count as real mp3.
    private const MP3_MIMES = ['audio/mpeg', 'audio/mp3', 'audio/mpga', 'audio/x-mpeg'];

    /* Gemini takes at most ~20 MB per request and base64 adds a third, so
       send files up to this size whole. Bigger ones need ffmpeg to make a
       smaller listening copy. */
    private const MAX_INLINE_AI_BYTES = 14 * 1024 * 1024;

    /* List active music tracks. Can filter by tags and search by title.
       A track must have all the chosen tags to show. */
    public function list(Request $request): JsonResponse
    {
        $this->logEvent('MusicTrack', 'list called', [
            'tags'   => $request->input('tags'),
            'search' => $request->input('search'),
        ]);

        $tracks = MusicTrack::visibleTo($this->caregiverId($request))->get();

        // Keep only tracks that have every chosen tag.
        $filterTags = $request->input('tags', []);
        if (is_array($filterTags) && count($filterTags) > 0) {
            $tracks = $tracks->filter(function (MusicTrack $t) use ($filterTags) {
                $trackTags = array_map('strtolower', $t->tagsArray());
                foreach ($filterTags as $ft) {
                    if (!in_array(strtolower(trim($ft)), $trackTags, true)) {
                        return false;
                    }
                }
                return true;
            });
        }

        // Search by title or composer.
        $search = trim((string) $request->input('search', ''));
        if ($search !== '') {
            $lower = strtolower($search);
            $tracks = $tracks->filter(function (MusicTrack $t) use ($lower) {
                $label = strtolower($t->title . '-' . $t->composer);
                return str_contains($label, $lower);
            });
        }

        return $this->successResponse('OK', [
            'tracks' => $tracks->values()->map(fn ($t) => $this->serialize($t)),
        ]);
    }

    /* All the tags used on active tracks, sorted. Fills the filter chips
       in the picker. */
    public function allTags(Request $request): JsonResponse
    {
        $this->logEvent('MusicTrack', 'allTags called');

        return $this->successResponse('OK', ['tags' => $this->tagVocabulary($this->caregiverId($request))]);
    }

    /* Given the tags already picked, return the other tags that can still
       be added (a track exists with all of them). Lets the picker hide
       tags that would give no results. */
    public function compatibleTags(Request $request): JsonResponse
    {
        $selected = $request->input('selected_tags', []);

        $active = MusicTrack::visibleTo($this->caregiverId($request))->get();

        // Tracks that match what's picked so far.
        $matching = $active->filter(function (MusicTrack $t) use ($selected) {
            $tt = array_map('strtolower', $t->tagsArray());
            foreach ($selected as $s) {
                if (!in_array(strtolower(trim($s)), $tt, true)) {
                    return false;
                }
            }
            return true;
        });

        // Tags on those tracks, minus the ones already picked.
        $selectedLower = array_map('strtolower', array_map('trim', $selected));

        $compatible = $matching
            ->flatMap(fn ($t) => $t->tagsArray())
            ->map(fn ($t) => trim($t))
            ->filter(fn ($t) => !in_array(strtolower($t), $selectedLower, true))
            ->unique()
            ->sort()
            ->values();

        return $this->successResponse('OK', ['tags' => $compatible]);
    }

    /* Caregiver uploads their own music. mp3 is kept as-is; other formats
       (mp4, m4a, wav...) are converted to mp3 with ffmpeg. If ffmpeg isn't
       available the caregiver is asked to upload an mp3 instead. Gemini then
       listens to the track and gives it mood tags, a tempo, a one-line
       summary, and any sensory cautions. The track is private to this
       caregiver. */
    public function upload(Request $request, GeminiService $gemini): JsonResponse
    {
        $file = $request->file('music_file');
        $this->logEvent('MusicTrack', 'upload called', [
            'name' => $file?->getClientOriginalName(),
            'size' => $file?->getSize(),
            'mime' => $file?->getMimeType(),
        ]);

        $validator = Validator::make($request->all(), [
            'music_file'    => 'required|file|max:40960',
            'title'         => 'nullable|string|max:200',
            'composer'      => 'nullable|string|max:200',
            'duration_secs' => 'nullable|integer|min:1|max:36000',
        ]);
        if ($validator->fails()) {
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $ext = strtolower($file->getClientOriginalExtension());
        if (!in_array($ext, self::UPLOAD_EXTENSIONS, true)) {
            return $this->errorResponse(
                'This file type is not supported. Please upload your music as an MP3 file.',
                'UNSUPPORTED_FORMAT',
                422
            );
        }

        $hasFfmpeg = $this->ffmpegAvailable();
        $isMp3 = in_array($file->getMimeType(), self::MP3_MIMES, true);

        // Anything that isn't really mp3 must be converted, which needs ffmpeg.
        if (!$isMp3 && !$hasFfmpeg) {
            $this->logWarn('MusicTrack', 'upload needs conversion but ffmpeg is missing', ['ext' => $ext]);
            return $this->errorResponse(
                "Converting .{$ext} files isn't available right now. Please upload your music as an MP3 file.",
                'MP3_ONLY',
                422
            );
        }

        $storedPath = 'uploads/bgm/' . Str::uuid() . '.mp3';
        $absPath = Storage::disk('public')->path($storedPath);
        Storage::disk('public')->makeDirectory('uploads/bgm');

        if ($isMp3) {
            Storage::disk('public')->putFileAs('uploads/bgm', $file, basename($storedPath));
        } elseif (!$this->convertToMp3($file->getRealPath(), $absPath)) {
            @unlink($absPath);
            return $this->errorResponse(
                "We couldn't convert this file to MP3 (it may have no sound track). Please upload your music as an MP3 file.",
                'CONVERSION_FAILED',
                422
            );
        }

        $caregiverId = $this->caregiverId($request);
        $title = trim((string) $request->input('title', ''));
        if ($title === '') {
            $title = $this->titleFromFilename($file->getClientOriginalName());
        }
        $duration = $hasFfmpeg ? $this->probeDuration($absPath) : null;
        $duration ??= $request->filled('duration_secs') ? (int) $request->input('duration_secs') : null;

        // Let the AI listen and tag it. Failure here never loses the upload.
        $analysis = null;
        if ($gemini->isConfigured()) {
            [$bytes, $cleanup] = $this->audioForAnalysis($absPath, $hasFfmpeg);
            if ($bytes !== null) {
                $analysis = $gemini->analyseMusic($bytes, 'audio/mp3', $title, $this->tagVocabulary($caregiverId)->all());
            }
            if ($cleanup) {
                @unlink($cleanup);
            }
        }

        $track = MusicTrack::create([
            'caregiver_id'  => $caregiverId,
            'title'         => mb_substr($title, 0, 200),
            'composer'      => $request->input('composer') ?: null,
            'file_path'     => 'storage/' . $storedPath,
            'tags'          => implode(',', $analysis['tags'] ?? []),
            'tempo'         => $analysis['tempo'] ?? null,
            'duration_secs' => $duration,
            'ai_summary'    => ($analysis['summary'] ?? '') ?: null,
            'sensory_notes' => ($analysis['sensory_notes'] ?? '') ?: null,
            'status'        => 'active',
        ]);

        $this->logEvent('MusicTrack', 'upload saved', [
            'track_id'  => $track->track_id,
            'converted' => !$isMp3,
            'ai_tagged' => $analysis !== null,
        ]);

        return $this->successResponse(
            $analysis !== null
                ? 'Music added and tagged'
                : 'Music added, but the AI could not tag it right now',
            [
                'track'     => $this->serialize($track),
                'converted' => !$isMp3,
                'ai_tagged' => $analysis !== null,
            ],
            201
        );
    }

    private function serialize(MusicTrack $t): array
    {
        return [
            'track_id'         => $t->track_id,
            'title'            => $t->title,
            'composer'         => $t->composer,
            'file_url'         => $this->mediaUrl($t->file_path),
            'tags'             => $t->tagsArray(),
            'tempo'            => $t->tempo,
            'duration_secs'    => $t->duration_secs,
            'is_user_uploaded' => $t->caregiver_id !== null,
            'ai_summary'       => $t->ai_summary,
            'sensory_notes'    => $t->sensory_notes,
        ];
    }

    private function caregiverId(Request $request): ?string
    {
        return $request->get('auth_caregiver')?->caregiver_id;
    }

    // Every tag on the tracks this caregiver can see, sorted.
    private function tagVocabulary(?string $caregiverId)
    {
        return MusicTrack::visibleTo($caregiverId)
            ->pluck('tags')
            ->flatMap(fn ($t) => array_map('trim', explode(',', $t)))
            ->filter()
            ->unique()
            ->sort()
            ->values();
    }

    private function ffmpegAvailable(): bool
    {
        try {
            return Process::timeout(10)->run([config('services.ffmpeg.path'), '-version'])->successful();
        } catch (\Throwable $e) {
            return false;
        }
    }

    // Re-encode any audio/video file to a stereo mp3. Video is dropped.
    private function convertToMp3(string $input, string $output): bool
    {
        try {
            $result = Process::timeout(300)->run([
                config('services.ffmpeg.path'), '-y', '-i', $input,
                '-vn', '-map_metadata', '-1',
                '-ac', '2', '-ar', '44100',
                '-codec:a', 'libmp3lame', '-q:a', '2',
                $output,
            ]);
            if (!$result->successful() || !is_file($output) || filesize($output) === 0) {
                $this->logWarn('MusicTrack', 'ffmpeg conversion failed', [
                    'error' => mb_substr($result->errorOutput(), -500),
                ]);
                return false;
            }
            return true;
        } catch (\Throwable $e) {
            $this->logWarn('MusicTrack', 'ffmpeg conversion exception', ['error' => $e->getMessage()]);
            return false;
        }
    }

    private function probeDuration(string $path): ?int
    {
        try {
            $result = Process::timeout(30)->run([
                config('services.ffmpeg.probe'), '-v', 'error',
                '-show_entries', 'format=duration',
                '-of', 'default=noprint_wrappers=1:nokey=1',
                $path,
            ]);
            $secs = (float) trim($result->output());
            return $result->successful() && $secs > 0 ? (int) round($secs) : null;
        } catch (\Throwable $e) {
            return null;
        }
    }

    /* Bytes to send to Gemini, plus a temp file to delete afterwards. With
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
                    return [file_get_contents($clip), $clip];
                }
            } catch (\Throwable $e) {
                $this->logWarn('MusicTrack', 'analysis clip failed', ['error' => $e->getMessage()]);
            }
            @unlink($clip);
        }

        if (filesize($mp3Path) <= self::MAX_INLINE_AI_BYTES) {
            return [file_get_contents($mp3Path), null];
        }
        $this->logWarn('MusicTrack', 'file too large to analyse without ffmpeg', [
            'bytes' => filesize($mp3Path),
        ]);
        return [null, null];
    }

    // "happy-kids_music.mp3" → "Happy Kids Music"
    private function titleFromFilename(string $name): string
    {
        $base = trim(preg_replace('/[\s_\-]+/', ' ', pathinfo($name, PATHINFO_FILENAME)));
        return $base !== '' ? Str::title($base) : 'My Music';
    }
}
