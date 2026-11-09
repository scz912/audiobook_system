<?php

namespace App\Http\Controllers\Api;

use App\Models\Caregiver;
use App\Models\CaregiverSettings;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class AuthController extends ApiController
{
    public function register(Request $request): JsonResponse
    {
        $this->logEvent('Auth', 'register called', [
            'email'  => $request->input('email'),
            'mobile' => $request->input('mobile_number'),
            'ip'     => $request->ip(),
        ]);

        $validator = Validator::make($request->all(), [
            'name'          => 'required|string|max:100',
            'pin'           => 'required|digits:4',
            'email'         => 'nullable|email|max:150|unique:caregivers,email',
            'mobile_number' => 'nullable|string|max:20|unique:caregivers,mobile_number',
            'device_id'     => 'nullable|string|max:255',
            'device_name'   => 'nullable|string|max:255',
            // 'independent' = a teenager using the app on their own.
            'account_type'  => 'nullable|in:caregiver,independent',
            'age'           => 'nullable|integer|min:1|max:18',
        ]);

        if ($validator->fails()) {
            $this->logWarn('Auth', 'register validation failed', [
                'errors' => $validator->errors()->all(),
            ]);
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        try {
            $independent = $request->input('account_type') === 'independent';
            $caregiver = DB::transaction(function () use ($request, $independent) {
                $caregiver = Caregiver::create([
                    'name'          => $request->input('name'),
                    'account_type'  => $independent ? 'independent' : 'caregiver',
                    'email'         => $request->input('email'),
                    'mobile_number' => $request->input('mobile_number'),
                    'pin'           => $request->input('pin'),
                    'device_id'     => $request->input('device_id'),
                    'device_name'   => $request->input('device_name'),
                    'is_active'     => true,
                ]);

                // Make a blank settings row.
                CaregiverSettings::create(['caregiver_id' => $caregiver->caregiver_id]);

                /* A teenager on their own is also the listener: one profile
                   for them, so moods, listening history and reading
                   settings work just as they do for a child. */
                if ($independent) {
                    $caregiver->childProfiles()->create([
                        'name' => $caregiver->name,
                        'age'  => (int) $request->input('age', 13),
                    ]);
                }
                return $caregiver;
            });

            $this->logEvent('Auth', 'register success', [
                'caregiver_id' => $caregiver->caregiver_id,
                'account_type' => $caregiver->account_type,
            ]);
            return $this->loginCaregiver($caregiver, $request);
        } catch (\Throwable $e) {
            $this->logError('Auth', 'register exception', [
                'error' => $e->getMessage(),
            ]);
            return $this->errorResponse('Could not register caregiver', 'REGISTER_FAILED', 500);
        }
    }

    public function loginWithPin(Request $request): JsonResponse
    {
        $this->logEvent('Auth', 'loginWithPin called', [
            'email'  => $request->input('email'),
            'mobile' => $request->input('mobile_number'),
            'ip'     => $request->ip(),
        ]);

        $validator = Validator::make($request->all(), [
            'pin'           => 'required|digits:4',
            'email'         => 'nullable|email',
            'mobile_number' => 'nullable|string|max:20',
            'device_id'     => 'nullable|string|max:255',
            'device_name'   => 'nullable|string|max:255',
            'fcm_token'     => 'nullable|string|max:500',
        ]);

        if ($validator->fails()) {
            $this->logWarn('Auth', 'login validation failed', [
                'errors' => $validator->errors()->all(),
            ]);
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        // Find caregiver by email, mobile, or fall back to demo mode.
        $query = Caregiver::query()->where('is_active', true);
        if ($request->filled('email')) {
            $query->where('email', $request->input('email'));
        } elseif ($request->filled('mobile_number')) {
            $query->where('mobile_number', $request->input('mobile_number'));
        } else {
            // Demo mode only works if there's just one caregiver.
            if (Caregiver::where('is_active', true)->count() !== 1) {
                $this->logWarn('Auth', 'login missing identifier');
                return $this->errorResponse(
                    'Please provide email or mobile number',
                    'IDENTIFIER_REQUIRED',
                    422
                );
            }
        }

        $caregiver = $query->first();
        if (!$caregiver || !$caregiver->verifyPin($request->input('pin'))) {
            $this->logWarn('Auth', 'login invalid credentials', [
                'identifier_found' => (bool) $caregiver,
            ]);
            return $this->errorResponse('Invalid credentials', 'INVALID_CREDENTIALS', 401);
        }

        $this->logEvent('Auth', 'login success', [
            'caregiver_id' => $caregiver->caregiver_id,
        ]);
        return $this->loginCaregiver($caregiver, $request);
    }

    private function loginCaregiver(Caregiver $caregiver, Request $request): JsonResponse
    {
        $token = Str::random(64);

        $caregiver->session_token   = $token;
        $caregiver->session_expires = Carbon::now('Asia/Kuala_Lumpur')->addHours(24);
        $caregiver->last_login_at   = Carbon::now('Asia/Kuala_Lumpur');
        if ($request->filled('device_id')) {
            $caregiver->device_id = $request->input('device_id');
        }
        if ($request->filled('device_name')) {
            $caregiver->device_name = $request->input('device_name');
        }
        if ($request->filled('fcm_token')) {
            $caregiver->fcm_token = $request->input('fcm_token');
        }
        $caregiver->save();

        return $this->successResponse('Login successful', [
            'session_token'   => $token,
            'session_expires' => $caregiver->session_expires->format('Y-m-d H:i:s'),
            'caregiver' => [
                'caregiver_id'  => $caregiver->caregiver_id,
                'name'          => $caregiver->name,
                'account_type'  => $caregiver->account_type ?? 'caregiver',
                'email'         => $caregiver->email,
                'mobile_number' => $caregiver->mobile_number,
            ],
        ]);
    }

    public function me(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $this->logEvent('Auth', 'me called', [
            'caregiver_id' => $caregiver->caregiver_id,
        ]);
        return $this->successResponse('OK', [
            'caregiver_id'  => $caregiver->caregiver_id,
            'name'          => $caregiver->name,
            'account_type'  => $caregiver->account_type ?? 'caregiver',
            'email'         => $caregiver->email,
            'mobile_number' => $caregiver->mobile_number,
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $this->logEvent('Auth', 'logout called', [
            'caregiver_id' => $caregiver->caregiver_id,
        ]);
        $caregiver->session_token   = null;
        $caregiver->session_expires = null;
        $caregiver->save();
        return $this->successResponse('Logged out');
    }

    public function verifyPin(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $this->logEvent('Auth', 'verifyPin called', [
            'caregiver_id' => $caregiver->caregiver_id,
        ]);
        $pin = (string) $request->input('pin');
        if (!preg_match('/^\d{4}$/', $pin)) {
            $this->logWarn('Auth', 'verifyPin bad format');
            return $this->errorResponse('PIN must be 4 digits', 'VALIDATION_ERROR', 422);
        }
        if (!$caregiver->verifyPin($pin)) {
            $this->logWarn('Auth', 'verifyPin mismatch', [
                'caregiver_id' => $caregiver->caregiver_id,
            ]);
            return $this->errorResponse('Invalid PIN', 'INVALID_PIN', 401);
        }
        return $this->successResponse('OK');
    }
}
