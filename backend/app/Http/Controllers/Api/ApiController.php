<?php

namespace App\Http\Controllers\Api;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Log;

/* Base for all /api controllers. Gives them the shared JSON
   success/error response format. */
abstract class ApiController
{
    protected function logEvent(string $tag, string $event, array $context = []): void
    {
        Log::info("[{$tag}] {$event}", $context);
    }

    protected function logWarn(string $tag, string $event, array $context = []): void
    {
        Log::warning("[{$tag}] {$event}", $context);
    }

    protected function logError(string $tag, string $event, array $context = []): void
    {
        Log::error("[{$tag}] {$event}", $context);
    }

    protected function successResponse(string $message, mixed $data = null, int $statusCode = 200): JsonResponse
    {
        $payload = [
            'status' => 'SUCCESS',
            'message' => $message,
            'timestamp' => now('Asia/Kuala_Lumpur')->format('Y-m-d H:i:s'),
        ];
        if ($data !== null) {
            $payload['data'] = $data;
        }
        return response()->json($payload, $statusCode);
    }

    protected function errorResponse(string $message, string $errorCode = 'ERROR', int $statusCode = 400): JsonResponse
    {
        return response()->json([
            'status' => 'ERROR',
            'message' => $message,
            'error_code' => $errorCode,
            'timestamp' => now('Asia/Kuala_Lumpur')->format('Y-m-d H:i:s'),
        ], $statusCode);
    }

    /* Stop the request if the caregiver hasn't joined the community.
       Returns an error response to send back, or null when they're a member. */
    protected function ensureMember($caregiver): ?JsonResponse
    {
        if (!$caregiver || !$caregiver->is_community_member) {
            return $this->errorResponse('Join the community first', 'NOT_A_MEMBER', 403);
        }
        return null;
    }

    /* Make a full URL from a stored path using the request's host, so it
       works for emulator and real devices alike. Full URLs (Gemini images)
       are left as-is. */
    protected function mediaUrl(?string $path): ?string
    {
        if ($path === null || $path === '') {
            return null;
        }
        if (\Illuminate\Support\Str::startsWith($path, ['http://', 'https://'])) {
            return $path;
        }
        $base = rtrim(request()->getSchemeAndHttpHost(), '/');
        return $base . '/' . ltrim($path, '/');
    }

    /* My settings for a contact, as the app reads them. An uploaded
       background comes back as a full URL. */
    protected function contactSettings(\App\Models\ContactSetting $s): array
    {
        $type = $s->background_type ?: 'none';
        return [
            'contact_id'  => $s->contact_id,
            'is_favorite' => (bool) $s->is_favorite,
            'is_blocked'  => (bool) $s->is_blocked,
            'is_muted'    => (bool) $s->is_muted,
            'background'  => [
                'type'  => $type,
                'value' => $type === 'image'
                    ? $this->mediaUrl($s->background_value)
                    : $s->background_value,
            ],
        ];
    }

    /* A book shared in a chat or hub post, as the card that shows it.
       in_my_library is true when the viewer made it or already saved a copy,
       so the card can say "In your library" instead of offering to save. */
    protected function sharedBook(?\App\Models\Audiobook $book, string $meId): ?array
    {
        if (!$book) {
            return null;
        }
        return [
            'audiobook_id'  => $book->audiobook_id,
            'title'         => $book->title,
            'author'        => $book->author,
            'language'      => $book->language,
            'book_format'   => $book->book_format ?? 'linear',
            'cover_image'   => $this->mediaUrl($book->cover_image),
            'in_my_library' => $book->isInLibraryOf($meId),
        ];
    }
}
