<?php

namespace App\Http\Middleware;

use App\Models\Caregiver;
use Carbon\Carbon;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

class SessionAuthMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        Log::info('[Auth] middleware enter', [
            'path'   => $request->path(),
            'method' => $request->method(),
            'ip'     => $request->ip(),
        ]);
        try {
            $authHeader = $request->header('Authorization');

            if (!$authHeader) {
                Log::warning('[Auth] middleware missing header', [
                    'path' => $request->path(),
                ]);
                return $this->unauthorized('Authorization header missing', 'MISSING_AUTH_HEADER');
            }

            $token = str_starts_with($authHeader, 'Bearer ')
                ? substr($authHeader, 7)
                : $authHeader;

            if (!$token) {
                Log::warning('[Auth] middleware invalid format', [
                    'path' => $request->path(),
                ]);
                return $this->unauthorized('Invalid authorization format', 'INVALID_AUTH_FORMAT');
            }

            $caregiver = Caregiver::where('session_token', $token)
                ->where('session_expires', '>', Carbon::now('Asia/Kuala_Lumpur'))
                ->where('is_active', true)
                ->first();

            if (!$caregiver) {
                Log::warning('[Auth] middleware invalid/expired token', [
                    'token_prefix' => substr($token, 0, 10) . '...',
                    'ip'           => $request->ip(),
                    'user_agent'   => $request->userAgent(),
                ]);
                return $this->unauthorized('Invalid or expired session token', 'INVALID_SESSION');
            }

            // If under 1h left, push the expiry out 24h.
            $minutesLeft = Carbon::now('Asia/Kuala_Lumpur')->diffInMinutes($caregiver->session_expires, false);
            if ($minutesLeft < 60) {
                $caregiver->session_expires = Carbon::now('Asia/Kuala_Lumpur')->addHours(24);
                $caregiver->save();
                Log::info('[Auth] middleware sliding expiry refreshed', [
                    'caregiver_id' => $caregiver->caregiver_id,
                ]);
            }

            $request->merge(['auth_caregiver' => $caregiver]);
            Log::info('[Auth] middleware authenticated', [
                'caregiver_id' => $caregiver->caregiver_id,
                'path'         => $request->path(),
            ]);

            return $next($request);
        } catch (\Throwable $e) {
            Log::error('[Auth] middleware exception', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
            return $this->unauthorized('Authentication failed', 'AUTH_ERROR');
        }
    }

    private function unauthorized(string $message, string $errorCode): Response
    {
        return response()->json([
            'status' => 'ERROR',
            'message' => $message,
            'error_code' => $errorCode,
            'timestamp' => now('Asia/Kuala_Lumpur')->format('Y-m-d H:i:s'),
        ], 401);
    }
}
