<?php

namespace App\Http\Controllers\Api;

use App\Models\ChildProfile;
use App\Models\ChildSettings;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class ChildProfileController extends ApiController
{
    public function index(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $this->logEvent('ChildProfile', 'index called', [
            'caregiver_id' => $caregiver->caregiver_id,
        ]);
        $profiles = $caregiver->childProfiles()->orderBy('created_at')->get()
            ->map(fn ($p) => $this->serialize($p));
        $this->logEvent('ChildProfile', 'index success', [
            'caregiver_id' => $caregiver->caregiver_id,
            'count'        => $profiles->count(),
        ]);
        return $this->successResponse('OK', $profiles);
    }

    public function store(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $this->logEvent('ChildProfile', 'store called', [
            'caregiver_id' => $caregiver->caregiver_id,
        ]);

        $validator = Validator::make($request->all(), [
            'name'           => 'required|string|max:50',
            'age'            => 'required|integer|min:1|max:18',
            'avatar_emoji'   => 'nullable|string|max:8',
            'avatar_color'   => 'nullable|string|max:9',
            'favorite_genre' => 'nullable|string|max:50',
        ]);

        if ($validator->fails()) {
            $this->logWarn('ChildProfile', 'store validation failed', [
                'errors' => $validator->errors()->all(),
            ]);
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $profile = $caregiver->childProfiles()->create([
            'name'           => $request->input('name'),
            'age'            => $request->input('age'),
            'avatar_emoji'   => $request->input('avatar_emoji', '🌟'),
            'avatar_color'   => $request->input('avatar_color', '#F5D5DD'),
            'favorite_genre' => $request->input('favorite_genre'),
        ]);

        $this->logEvent('ChildProfile', 'store success', [
            'caregiver_id' => $caregiver->caregiver_id,
            'child_id'     => $profile->child_id,
        ]);
        return $this->successResponse('Profile created', $this->serialize($profile));
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $this->logEvent('ChildProfile', 'update called', [
            'caregiver_id' => $caregiver->caregiver_id,
            'child_id'     => $id,
        ]);

        $profile = $caregiver->childProfiles()->where('child_id', $id)->first();
        if (!$profile) {
            $this->logWarn('ChildProfile', 'update not found', [
                'caregiver_id' => $caregiver->caregiver_id,
                'child_id'     => $id,
            ]);
            return $this->errorResponse('Profile not found', 'NOT_FOUND', 404);
        }

        $validator = Validator::make($request->all(), [
            'name'              => 'sometimes|string|max:50',
            'age'               => 'sometimes|integer|min:1|max:18',
            'avatar_emoji'      => 'sometimes|string|max:8',
            'avatar_color'      => 'sometimes|string|max:9',
            'favorite_genre'    => 'sometimes|nullable|string|max:50',
            'listening_minutes' => 'sometimes|integer|min:0',
        ]);

        if ($validator->fails()) {
            $this->logWarn('ChildProfile', 'update validation failed', [
                'errors' => $validator->errors()->all(),
            ]);
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $profile->fill($validator->validated())->save();
        $this->logEvent('ChildProfile', 'update success', [
            'child_id' => $profile->child_id,
        ]);
        return $this->successResponse('Profile updated', $this->serialize($profile));
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $this->logEvent('ChildProfile', 'destroy called', [
            'caregiver_id' => $caregiver->caregiver_id,
            'child_id'     => $id,
        ]);
        $profile = $caregiver->childProfiles()->where('child_id', $id)->first();
        if (!$profile) {
            $this->logWarn('ChildProfile', 'destroy not found', [
                'child_id' => $id,
            ]);
            return $this->errorResponse('Profile not found', 'NOT_FOUND', 404);
        }
        $profile->delete();
        $this->logEvent('ChildProfile', 'destroy success', [
            'child_id' => $id,
        ]);
        return $this->successResponse('Profile deleted');
    }

    /* Per-child voice and playback settings. Makes a default row the
       first time it's asked for. */
    public function showSettings(Request $request, string $id): JsonResponse
    {
        $this->logEvent('ChildProfile', 'showSettings called', [
            'child_id' => $id,
        ]);
        $profile = $this->ownedProfile($request, $id);
        if (!$profile) {
            $this->logWarn('ChildProfile', 'showSettings not found', [
                'child_id' => $id,
            ]);
            return $this->errorResponse('Profile not found', 'NOT_FOUND', 404);
        }
        $settings = $profile->childSettings
            ?? ChildSettings::create(['child_id' => $profile->child_id]);
        return $this->successResponse('OK', $this->serializeSettings($settings));
    }

    public function updateSettings(Request $request, string $id): JsonResponse
    {
        $this->logEvent('ChildProfile', 'updateSettings called', [
            'child_id' => $id,
            'fields'   => array_keys($request->all()),
        ]);
        $profile = $this->ownedProfile($request, $id);
        if (!$profile) {
            $this->logWarn('ChildProfile', 'updateSettings not found', [
                'child_id' => $id,
            ]);
            return $this->errorResponse('Profile not found', 'NOT_FOUND', 404);
        }

        $validator = Validator::make($request->all(), [
            'narrator_voice'     => 'sometimes|in:' . implode(',', ChildSettings::ALLOWED_VOICES),
            'reading_speed'      => 'sometimes|numeric|min:0.5|max:2.0',
            'volume'             => 'sometimes|numeric|min:0|max:1',
            'text_scale'         => 'sometimes|numeric|min:0.7|max:2.0',
            'reduced_animations' => 'sometimes|boolean',
            'auto_play_next'     => 'sometimes|boolean',
            'read_along'         => 'sometimes|boolean',
        ]);

        if ($validator->fails()) {
            $this->logWarn('ChildProfile', 'updateSettings validation failed', [
                'errors' => $validator->errors()->all(),
            ]);
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $settings = $profile->childSettings
            ?? ChildSettings::create(['child_id' => $profile->child_id]);
        $settings->fill($validator->validated())->save();

        $this->logEvent('ChildProfile', 'updateSettings success', [
            'child_id' => $profile->child_id,
        ]);
        return $this->successResponse('Settings updated', $this->serializeSettings($settings));
    }

    private function ownedProfile(Request $request, string $id): ?ChildProfile
    {
        $caregiver = $request->get('auth_caregiver');
        return $caregiver->childProfiles()->where('child_id', $id)->first();
    }

    private function serializeSettings(ChildSettings $s): array
    {
        return [
            'setting_id'         => $s->setting_id,
            'child_id'           => $s->child_id,
            'narrator_voice'     => $s->narrator_voice,
            'reading_speed'      => (float) $s->reading_speed,
            'volume'             => (float) $s->volume,
            'text_scale'         => (float) $s->text_scale,
            'reduced_animations' => (bool) $s->reduced_animations,
            'auto_play_next'     => (bool) $s->auto_play_next,
            'read_along'         => (bool) $s->read_along,
        ];
    }

    private function serialize(ChildProfile $p): array
    {
        return [
            'child_id'          => $p->child_id,
            'caregiver_id'      => $p->caregiver_id,
            'name'              => $p->name,
            'age'               => $p->age,
            'avatar_emoji'      => $p->avatar_emoji,
            'avatar_color'      => $p->avatar_color,
            'favorite_genre'    => $p->favorite_genre,
            'listening_minutes' => $p->listening_minutes,
            'created_at'        => $p->created_at?->format('Y-m-d H:i:s'),
            'updated_at'        => $p->updated_at?->format('Y-m-d H:i:s'),
        ];
    }
}
