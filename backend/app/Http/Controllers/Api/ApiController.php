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
}
