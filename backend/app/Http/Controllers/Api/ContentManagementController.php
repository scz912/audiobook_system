<?php

namespace App\Http\Controllers\Api;

use App\Jobs\GenerateAudiobookImages;
use App\Models\Audiobook;
use App\Models\MusicTrack;
use App\Services\GeminiService;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Validator;

class ContentManagementController extends ApiController
{
    public function getContentSummary(Request $request): JsonResponse
    {
        $this->logEvent('Content', 'getContentSummary called');
        try {
            return $this->successResponse('Content summary retrieved successfully', [
                'total_items'  => Audiobook::count(),
                'audio_files'  => Audiobook::where('type', 'Audio')->count(),
                'text_files'   => Audiobook::where('type', 'Text')->count(),
                'ai_generated' => Audiobook::where('is_generated', 1)->count(),
            ]);
        } catch (\Throwable $e) {
            $this->logError('Content', 'getContentSummary exception', [
                'error' => $e->getMessage(),
            ]);
            return $this->errorResponse('Internal server error', 'SERVER_ERROR', 500);
        }
    }

    public function getContentList(Request $request): JsonResponse
    {
        $this->logEvent('Content', 'getContentList called', [
            'filter_type' => $request->input('filter_type'),
            'search'      => $request->input('search'),
            'category'    => $request->input('category'),
            'age_group'   => $request->input('age_group'),
            'language'    => $request->input('language'),
        ]);
        try {
            $query = Audiobook::query()->orderByDesc('created_at');

            if ($request->filled('filter_type')) {
                $filter = strtolower($request->input('filter_type'));
                if ($filter === 'audio') {
                    $query->where('type', 'Audio')->where('is_generated', 0);
                } elseif ($filter === 'text') {
                    $query->where('type', 'Text')->where('is_generated', 0);
                } elseif ($filter === 'ai') {
                    $query->where('is_generated', 1);
                }
            }

            if ($request->filled('search')) {
                $search = '%' . $request->input('search') . '%';
                $query->where(function ($q) use ($search) {
                    $q->where('title', 'like', $search)
                      ->orWhere('author', 'like', $search)
                      ->orWhere('topic', 'like', $search)
                      ->orWhere('category', 'like', $search)
                      ->orWhere('tags', 'like', $search);
                });
            }

            if ($request->filled('category')) {
                $query->where('category', $request->input('category'));
            }

            if ($request->filled('age_group')) {
                $query->where('age_group', $request->input('age_group'));
            }

            // Let the library filter by language (en or ms).
            if ($request->filled('language')) {
                $query->where('language', strtolower($request->input('language')));
            }

            $items = $query->get()->map(fn ($item) => $this->serialize($item))->toArray();

            $this->logEvent('Content', 'getContentList success', [
                'count' => count($items),
            ]);
            return $this->successResponse('Content list retrieved successfully', [
                'items' => $items,
            ]);
        } catch (\Throwable $e) {
            $this->logError('Content', 'getContentList exception', [
                'error' => $e->getMessage(),
            ]);
            return $this->errorResponse('Internal server error', 'SERVER_ERROR', 500);
        }
    }

    public function createContent(Request $request): JsonResponse
    {
        $this->logEvent('Content', 'createContent called', [
            'title'        => $request->input('title'),
            'has_audio'    => $request->hasFile('audio_file'),
            'has_video'    => $request->hasFile('video_file'),
            'has_cover'    => $request->hasFile('cover_image'),
            'has_source'   => $request->hasFile('source_file'),
            'language'     => $request->input('language'),
            'is_generated' => $request->boolean('is_generated'),
        ]);
        $validator = Validator::make($request->all(), [
            'title'        => 'required|string|max:255',
            'topic'        => 'nullable|string|max:100',
            'category'     => 'nullable|string|max:100',
            'difficulty'   => 'nullable|in:easy,medium,hard,Easy,Medium,Hard',
            'type'         => 'nullable|in:Audio,Text,Video',
            'tags'         => 'nullable|string',
            'content_text' => 'nullable|string',
            'description'  => 'nullable|string',
            'age_group'    => 'nullable|string|max:50',
            'is_generated' => 'nullable|boolean',
            'language'     => 'nullable|in:en,ms',
            'source_file'  => 'nullable|file|mimes:pdf,txt,mp3,wav|max:10240',
            /* Check the file's real type, not its name, and cover the
               audio types phone pickers send. The plain "mp3,wav" rule
               sometimes wrongly rejects valid files. */
            'audio_file'   => 'nullable|file|max:20480|mimetypes:audio/mpeg,audio/mp3,audio/mpga,audio/wav,audio/x-wav,audio/wave,audio/vnd.wave,audio/x-pn-wav,audio/mp4,audio/x-m4a,audio/aac,audio/x-aac,audio/ogg,audio/vorbis,audio/flac,audio/webm',
            'video_file'   => 'nullable|file|mimes:mp4,mov,webm|max:51200',
            'cover_image'  => 'nullable|image|mimes:jpg,jpeg,png|max:5120',
            'track_id'     => 'nullable|uuid|exists:music_tracks,track_id',
            'bgm_volume'   => 'nullable|integer|min:0|max:100',
        ]);

        if ($validator->fails()) {
            $this->logWarn('Content', 'createContent validation failed', [
                'errors' => $validator->errors()->all(),
            ]);
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        try {
            $sourceFilePath = null;
            $audioFilePath  = null;
            $videoFilePath  = null;
            $coverImagePath = null;

            if ($request->hasFile('source_file')) {
                $sourceFilePath = 'storage/' . $request->file('source_file')->store('uploads/content', 'public');
            }
            if ($request->hasFile('audio_file')) {
                $audioFilePath = 'storage/' . $request->file('audio_file')->store('uploads/audio', 'public');
            }
            if ($request->hasFile('video_file')) {
                $videoFilePath = 'storage/' . $request->file('video_file')->store('uploads/video', 'public');
            }
            if ($request->hasFile('cover_image')) {
                $coverImagePath = 'storage/' . $request->file('cover_image')->store('uploads/covers', 'public');
            }

            $isGenerated = $request->boolean('is_generated');
            $type = $request->input('type')
                ?? ($videoFilePath ? 'Video' : ($audioFilePath ? 'Audio' : 'Text'));
            $difficulty = strtolower((string) $request->input('difficulty', 'easy'));

            $content = Audiobook::create([
                'title'            => $request->input('title'),
                'topic'            => $request->input('topic'),
                'category'         => $request->input('category'),
                'difficulty'       => $difficulty,
                'type'             => $type,
                'tags'             => $request->input('tags'),
                'description'     => $request->input('description'),
                'content_text'     => $request->input('content_text'),
                'age_group'        => $request->input('age_group'),
                'language'         => $request->input('language') ?: 'en',
                'source_file'      => $sourceFilePath,
                'audio_file'       => $audioFilePath,
                'video_file'       => $videoFilePath,
                'cover_image'      => $coverImagePath,
                'is_generated'     => $isGenerated,
                'is_user_uploaded' => true,
                'status'           => $isGenerated ? 'processing' : 'available',
                'track_id'         => $request->input('track_id') ?: null,
                'bgm_volume'       => $request->filled('bgm_volume') ? (int) $request->input('bgm_volume') : 30,
            ]);

            $this->logEvent('Content', 'createContent success', [
                'audiobook_id' => $content->audiobook_id,
                'type'         => $content->type,
            ]);
            return $this->successResponse('Content uploaded successfully', $this->serialize($content));
        } catch (\Throwable $e) {
            $this->logError('Content', 'createContent exception', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
            return $this->errorResponse('Internal server error', 'SERVER_ERROR', 500);
        }
    }

    /* Make a story (and cover) with Gemini and save it as a new audiobook.
       This is the caregiver's "Generate with AI" flow. */
    public function generateContent(Request $request, GeminiService $gemini): JsonResponse
    {
        $this->logEvent('Content', 'generateContent called', [
            'topic'          => $request->input('topic'),
            'age_group'      => $request->input('age_group'),
            'page_count'     => $request->input('page_count'),
            'language'       => $request->input('language'),
            'generate_image' => $request->boolean('generate_image'),
        ]);
        $validator = Validator::make($request->all(), [
            'topic'          => 'required|string|max:255',
            'age_group'      => 'nullable|string|max:50',
            'category'       => 'nullable|string|max:100',
            'difficulty'     => 'nullable|in:easy,medium,hard,Easy,Medium,Hard',
            'tags'           => 'nullable|string',
            'source_text'    => 'nullable|string',
            'generate_image' => 'nullable|boolean',
            'page_count'     => 'nullable|integer|min:1|max:20',
            'language'       => 'nullable|in:en,ms',
            'track_id'       => 'nullable|uuid|exists:music_tracks,track_id',
            'bgm_volume'     => 'nullable|integer|min:0|max:100',
        ]);

        if ($validator->fails()) {
            $this->logWarn('Content', 'generateContent validation failed', [
                'errors' => $validator->errors()->all(),
            ]);
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        if (!$gemini->isConfigured()) {
            $this->logWarn('Content', 'generateContent AI not configured');
            return $this->errorResponse(
                'AI is not configured. Add GEMINI_API_KEY to the backend .env file.',
                'AI_NOT_CONFIGURED',
                503
            );
        }

        try {
            $story = $gemini->generateStory(
                $request->input('topic'),
                $request->input('age_group'),
                $request->input('source_text'),
                $request->filled('page_count') ? (int) $request->input('page_count') : null,
                $request->input('language'),
            );

            $generateImages = $request->boolean('generate_image');

            /* Text is ready now, but each page image takes ~12s. So we
               save the book as "processing", then the GenerateAudiobookImages
               job draws the pictures and flips it to "available".

               With QUEUE_CONNECTION=sync (the default) the job runs right
               here, so the book is done when we reply. With =database it
               runs in the background and the app shows a pending state. */
            $content = Audiobook::create([
                // Keep the caregiver's title, not the AI's made-up one.
                'title'            => trim((string) $request->input('topic')),
                'topic'            => $request->input('topic'),
                'category'         => $request->input('category'),
                'difficulty'       => strtolower((string) $request->input('difficulty', 'easy')),
                'type'             => 'Text',
                'tags'             => $request->input('tags'),
                'content_text'     => $story['content'],
                'age_group'        => $request->input('age_group'),
                'language'         => $request->input('language') ?: 'en',
                'is_generated'     => true,
                'is_user_uploaded' => true,
                'status'           => $generateImages ? 'processing' : 'available',
                'track_id'         => $this->resolveTrackId($request, $story['content'] ?? ''),
                'bgm_volume'       => $request->filled('bgm_volume') ? (int) $request->input('bgm_volume') : 30,
            ]);

            foreach ($story['pages'] as $i => $page) {
                $content->pages()->create([
                    'page_number'  => $i + 1,
                    'text'         => $page['text'],
                    'image_prompt' => $page['image_prompt'],
                    'image'        => null,
                ]);
            }

            if ($generateImages) {
                @set_time_limit(0); // inline image generation can take ~1 minute
                @ignore_user_abort(true); // finish even if the client navigates away
                GenerateAudiobookImages::dispatch($content->audiobook_id);
                $content->refresh(); // 'available' now if the job ran inline (sync)
            }

            // Make the voice clips now so the first preview plays fast.
            if ($gemini->isConfigured()) {
                foreach ($content->pages as $pg) {
                    if (!empty($pg->text)) {
                        try { $gemini->generateSpeech(trim($pg->text), 'Kore'); } catch (\Throwable $_) {}
                    }
                }
            }

            $ready = $content->status === 'available';
            $message = !$generateImages
                ? 'AI story generated.'
                : ($ready
                    ? 'Your storybook is ready, with a picture on every page!'
                    : 'Your storybook is being created — it will appear in the library when ready.');

            $this->logEvent('Content', 'generateContent success', [
                'audiobook_id'    => $content->audiobook_id,
                'pages'           => count($story['pages']),
                'status'          => $content->status,
                'generate_images' => $generateImages,
            ]);
            return $this->successResponse($message, $this->serialize($content->load('pages')));
        } catch (\Throwable $e) {
            $this->logError('Content', 'generateContent exception', [
                'error' => $e->getMessage(),
            ]);
            return $this->errorResponse(
                'AI generation failed: ' . $e->getMessage(),
                'AI_FAILED',
                502
            );
        }
    }

    /* Update an audiobook's details like title, description and language.
       Doesn't change the pages, audio, or cover, those have their own flows. */
    public function update(Request $request, string $audiobookId): JsonResponse
    {
        $this->logEvent('Content', 'update called', [
            'audiobook_id' => $audiobookId,
            'fields'       => array_keys($request->all()),
        ]);

        $book = Audiobook::where('audiobook_id', $audiobookId)->first();
        if (!$book) {
            $this->logWarn('Content', 'update not found', [
                'audiobook_id' => $audiobookId,
            ]);
            return $this->errorResponse('Audiobook not found', 'NOT_FOUND', 404);
        }

        $validator = Validator::make($request->all(), [
            'title'        => 'sometimes|string|max:255',
            'topic'        => 'sometimes|nullable|string|max:100',
            'category'     => 'sometimes|nullable|string|max:100',
            'difficulty'   => 'sometimes|nullable|in:easy,medium,hard,Easy,Medium,Hard',
            'tags'         => 'sometimes|nullable|string',
            'description'  => 'sometimes|nullable|string',
            'age_group'    => 'sometimes|nullable|string|max:50',
            'language'     => 'sometimes|in:en,ms',
        ]);

        if ($validator->fails()) {
            $this->logWarn('Content', 'update validation failed', [
                'errors' => $validator->errors()->all(),
            ]);
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        try {
            $book->fill($validator->validated())->save();
            $this->logEvent('Content', 'update success', [
                'audiobook_id' => $book->audiobook_id,
            ]);
            return $this->successResponse('Content updated', $this->serialize($book->load('pages')));
        } catch (\Throwable $e) {
            $this->logError('Content', 'update exception', [
                'audiobook_id' => $audiobookId,
                'error'        => $e->getMessage(),
            ]);
            return $this->errorResponse('Could not update content', 'SERVER_ERROR', 500);
        }
    }

    /* Delete an audiobook. The database cleans up its pages and listening
       history on its own (ON DELETE CASCADE). */
    public function destroy(Request $request, string $audiobookId): JsonResponse
    {
        $this->logEvent('Content', 'destroy called', [
            'audiobook_id' => $audiobookId,
        ]);

        $book = Audiobook::where('audiobook_id', $audiobookId)->first();
        if (!$book) {
            $this->logWarn('Content', 'destroy not found', [
                'audiobook_id' => $audiobookId,
            ]);
            return $this->errorResponse('Audiobook not found', 'NOT_FOUND', 404);
        }

        try {
            $book->delete();
            $this->logEvent('Content', 'destroy success', [
                'audiobook_id' => $audiobookId,
            ]);
            return $this->successResponse('Content deleted');
        } catch (\Throwable $e) {
            $this->logError('Content', 'destroy exception', [
                'audiobook_id' => $audiobookId,
                'error'        => $e->getMessage(),
            ]);
            return $this->errorResponse('Could not delete content', 'SERVER_ERROR', 500);
        }
    }

    /* Update one page (text, image, or audio boundary). Multipart so a new
       image can come with the text. The image is optional — leave it out to
       keep the current one. */
    public function updatePage(Request $request, string $audiobookId, string $pageId): JsonResponse
    {
        $this->logEvent('Content', 'updatePage called', [
            'audiobook_id' => $audiobookId,
            'page_id'      => $pageId,
            'has_image'    => $request->hasFile('image'),
            'fields'       => array_keys($request->all()),
        ]);

        $book = Audiobook::where('audiobook_id', $audiobookId)->first();
        if (!$book) {
            $this->logWarn('Content', 'updatePage book not found', [
                'audiobook_id' => $audiobookId,
            ]);
            return $this->errorResponse('Audiobook not found', 'NOT_FOUND', 404);
        }
        $page = $book->pages()->where('page_id', $pageId)->first();
        if (!$page) {
            $this->logWarn('Content', 'updatePage page not found', [
                'audiobook_id' => $audiobookId,
                'page_id'      => $pageId,
            ]);
            return $this->errorResponse('Page not found', 'NOT_FOUND', 404);
        }

        $validator = Validator::make($request->all(), [
            'text'           => 'sometimes|nullable|string',
            'page_number'    => 'sometimes|integer|min:1',
            'image'          => 'sometimes|nullable|image|mimes:jpg,jpeg,png,webp|max:5120',
            'audio_start_ms' => 'sometimes|nullable|integer|min:0',
        ]);
        if ($validator->fails()) {
            $this->logWarn('Content', 'updatePage validation failed', [
                'errors' => $validator->errors()->all(),
            ]);
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        try {
            $patch = [];
            if ($request->has('text')) {
                $patch['text'] = $request->input('text');
            }
            if ($request->filled('page_number')) {
                $patch['page_number'] = (int) $request->input('page_number');
            }
            if ($request->has('audio_start_ms')) {
                $patch['audio_start_ms'] = $request->filled('audio_start_ms')
                    ? (int) $request->input('audio_start_ms')
                    : null;
            }
            if ($request->hasFile('image')) {
                $patch['image'] = 'storage/' . $request->file('image')
                    ->store('uploads/pages', 'public');
            }

            $page->fill($patch)->save();

            $this->logEvent('Content', 'updatePage success', [
                'audiobook_id' => $book->audiobook_id,
                'page_id'      => $page->page_id,
            ]);
            return $this->successResponse('Page updated', [
                'page_id'        => $page->page_id,
                'page_number'    => $page->page_number,
                'text'           => $page->text,
                'image'          => $this->mediaUrl($page->image),
                'audio_start_ms' => $page->audio_start_ms,
            ]);
        } catch (\Throwable $e) {
            $this->logError('Content', 'updatePage exception', [
                'audiobook_id' => $audiobookId,
                'page_id'      => $pageId,
                'error'        => $e->getMessage(),
            ]);
            return $this->errorResponse('Could not update page', 'SERVER_ERROR', 500);
        }
    }

    /* Delete one page. The other pages keep their numbers — the caller can
       renumber with updatePage if needed. */
    public function deletePage(Request $request, string $audiobookId, string $pageId): JsonResponse
    {
        $this->logEvent('Content', 'deletePage called', [
            'audiobook_id' => $audiobookId,
            'page_id'      => $pageId,
        ]);
        $book = Audiobook::where('audiobook_id', $audiobookId)->first();
        if (!$book) {
            $this->logWarn('Content', 'deletePage book not found', [
                'audiobook_id' => $audiobookId,
            ]);
            return $this->errorResponse('Audiobook not found', 'NOT_FOUND', 404);
        }
        $page = $book->pages()->where('page_id', $pageId)->first();
        if (!$page) {
            $this->logWarn('Content', 'deletePage page not found', [
                'page_id' => $pageId,
            ]);
            return $this->errorResponse('Page not found', 'NOT_FOUND', 404);
        }

        try {
            $page->delete();
            $this->logEvent('Content', 'deletePage success', [
                'audiobook_id' => $audiobookId,
                'page_id'      => $pageId,
            ]);
            return $this->successResponse('Page deleted');
        } catch (\Throwable $e) {
            $this->logError('Content', 'deletePage exception', [
                'audiobook_id' => $audiobookId,
                'page_id'      => $pageId,
                'error'        => $e->getMessage(),
            ]);
            return $this->errorResponse('Could not delete page', 'SERVER_ERROR', 500);
        }
    }

    /* Add one page (text + optional image) to an audiobook.
       Multipart: text, image file, page_number. */
    public function addPage(Request $request, string $audiobookId, GeminiService $gemini): JsonResponse
    {
        $this->logEvent('Content', 'addPage called', [
            'audiobook_id' => $audiobookId,
            'has_image'    => $request->hasFile('image'),
        ]);
        $book = Audiobook::where('audiobook_id', $audiobookId)->first();
        if (!$book) {
            $this->logWarn('Content', 'addPage book not found', [
                'audiobook_id' => $audiobookId,
            ]);
            return $this->errorResponse('Audiobook not found', 'NOT_FOUND', 404);
        }

        $validator = Validator::make($request->all(), [
            'text'           => 'nullable|string',
            'page_number'    => 'nullable|integer|min:1',
            'image'          => 'nullable|image|mimes:jpg,jpeg,png,webp|max:5120',
            // Where this page starts in the whole-book recording.
            'audio_start_ms' => 'nullable|integer|min:0',
        ]);

        if ($validator->fails()) {
            $this->logWarn('Content', 'addPage validation failed', [
                'errors' => $validator->errors()->all(),
            ]);
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        try {
            $imagePath = null;
            if ($request->hasFile('image')) {
                $imagePath = 'storage/' . $request->file('image')->store('uploads/pages', 'public');
            }

            $pageNumber = (int) $request->input('page_number', $book->pages()->count() + 1);

            $page = $book->pages()->create([
                'page_number'    => $pageNumber,
                'text'           => $request->input('text'),
                'image'          => $imagePath,
                'audio_start_ms' => $request->filled('audio_start_ms')
                    ? (int) $request->input('audio_start_ms')
                    : null,
            ]);

            // Use page 1's image as the cover if there isn't one.
            if ($imagePath && empty($book->cover_image) && $pageNumber === 1) {
                $book->cover_image = $imagePath;
                $book->save();
            }

            // Make the voice clip now so the first playback is instant.
            if (!empty($page->text) && $gemini->isConfigured()) {
                try { $gemini->generateSpeech(trim($page->text), 'Kore'); } catch (\Throwable $_) {}
            }

            $this->logEvent('Content', 'addPage success', [
                'audiobook_id' => $book->audiobook_id,
                'page_id'      => $page->page_id,
                'page_number'  => $page->page_number,
            ]);
            return $this->successResponse('Page added', [
                'page_id'     => $page->page_id,
                'page_number' => $page->page_number,
                'text'        => $page->text,
                'image'       => $this->mediaUrl($page->image),
            ]);
        } catch (\Throwable $e) {
            $this->logError('Content', 'addPage exception', [
                'audiobook_id' => $audiobookId,
                'error'        => $e->getMessage(),
            ]);
            return $this->errorResponse('Could not add page', 'SERVER_ERROR', 500);
        }
    }

    private function serializePages(Audiobook $item): array
    {
        return $item->pages->map(fn ($p) => [
            'page_id'     => $p->page_id,
            'page_number' => $p->page_number,
            'text'        => $p->text,
            'image'       => $this->mediaUrl($p->image),
        ])->toArray();
    }

    private function serialize(Audiobook $item): array
    {
        $track = $item->track_id ? MusicTrack::find($item->track_id) : null;
        return [
            'audiobook_id'     => $item->audiobook_id,
            'title'            => $item->title,
            'author'           => $item->author,
            'description'      => $item->description,
            'topic'            => $item->topic,
            'category'         => $item->category,
            'difficulty'       => $item->difficulty,
            'type'             => $item->type,
            'content_text'     => $item->content_text,
            'audio_file'       => $this->mediaUrl($item->audio_file),
            'video_file'       => $this->mediaUrl($item->video_file),
            'source_file'      => $this->mediaUrl($item->source_file),
            'cover_image'      => $this->mediaUrl($item->cover_image),
            'duration_minutes' => $item->duration_minutes,
            'language'         => $item->language,
            'age_group'        => $item->age_group,
            'tags'             => $item->tags,
            'is_generated'     => (bool) $item->is_generated,
            'is_user_uploaded' => (bool) $item->is_user_uploaded,
            'status'           => $item->status,
            'track_id'         => $item->track_id,
            'bgm_volume'       => (int) ($item->bgm_volume ?? 30),
            'music_track'      => $track ? [
                'track_id'      => $track->track_id,
                'title'         => $track->title,
                'composer'      => $track->composer,
                'file_url'      => $this->mediaUrl($track->file_path),
                'tags'          => $track->tagsArray(),
                'duration_secs' => $track->duration_secs,
            ] : null,
            'pages'            => $this->serializePages($item),
            'created_at'       => $item->created_at ? Carbon::parse($item->created_at)->format('Y-m-d H:i:s') : null,
            'updated_at'       => $item->updated_at ? Carbon::parse($item->updated_at)->format('Y-m-d H:i:s') : null,
        ];
    }

    /* Pick the music track. Use the caregiver's choice if they made one.
       If they turned music on but left it on auto, pick the best match
       from the story words. If music is off, return null. */
    private function resolveTrackId(Request $request, string $storyContent): ?string
    {
        // Caregiver picked a track.
        if ($request->filled('track_id')) {
            return $request->input('track_id');
        }

        // No track_id at all → music is off.
        if (!$request->has('track_id')) {
            return null;
        }

        // track_id is there but blank → auto-pick from the story.
        return $this->autoSelectTrack($storyContent);
    }

    /* Score each track against the story words and return the best match,
       or null if nothing scores. */
    private function autoSelectTrack(string $content): ?string
    {
        $content = strtolower($content);

        // Word → mood tags, used for scoring.
        $keywords = [
            'happy'       => ['Happy', 'Upbeat', 'Energetic'],
            'fun'         => ['Playful', 'Energetic', 'Happy'],
            'play'        => ['Playful', 'Energetic'],
            'laugh'       => ['Happy', 'Upbeat'],
            'excit'       => ['Energetic', 'Upbeat'],
            'adventure'   => ['Adventurous', 'Curious'],
            'explor'      => ['Adventurous', 'Curious', 'Imaginative'],
            'magic'       => ['Whimsical', 'Imaginative'],
            'wonder'      => ['Whimsical', 'Imaginative', 'Curious'],
            'dream'       => ['Whimsical', 'Imaginative', 'Calm'],
            'mystery'     => ['Mysterious', 'Curious'],
            'secret'      => ['Mysterious', 'Curious'],
            'calm'        => ['Calm', 'Peaceful', 'Gentle'],
            'sleep'       => ['Calm', 'Soothing', 'Relaxing', 'Peaceful'],
            'quiet'       => ['Calm', 'Peaceful'],
            'gentle'      => ['Gentle', 'Calm'],
            'sad'         => ['Calm', 'Gentle', 'Peaceful'],
            'rain'        => ['Calm', 'Soothing', 'Peaceful'],
            'nature'      => ['Calm', 'Peaceful'],
            'friend'      => ['Gentle', 'Playful', 'Whimsical'],
            'story'       => ['Whimsical', 'Gentle'],
            'once upon'   => ['Whimsical', 'Imaginative'],
            'forest'      => ['Adventurous', 'Calm'],
            'star'        => ['Imaginative', 'Whimsical'],
        ];

        $tracks = MusicTrack::where('status', 'active')->get();
        $scores = [];

        foreach ($tracks as $track) {
            $scores[$track->track_id] = 0;
            $trackTags = array_map('strtolower', $track->tagsArray());

            foreach ($keywords as $kw => $moods) {
                if (str_contains($content, $kw)) {
                    foreach ($moods as $mood) {
                        if (in_array(strtolower($mood), $trackTags, true)) {
                            $scores[$track->track_id]++;
                        }
                    }
                }
            }
        }

        arsort($scores);
        $best = array_key_first($scores);

        // Only match if at least one word scored.
        return ($best !== null && $scores[$best] > 0) ? $best : ($tracks->first()?->track_id);
    }
}
