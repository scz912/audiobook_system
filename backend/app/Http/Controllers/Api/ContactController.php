<?php

namespace App\Http\Controllers\Api;

use App\Models\Caregiver;
use App\Models\ContactSetting;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

/* My settings for other members: favorite, block, mute, and the chat
   background. Also the lists behind Settings > Favorite / Blocked contacts. */
class ContactController extends ApiController
{
    public function show(Request $request, string $contactId): JsonResponse
    {
        $me = $request->get('auth_caregiver');
        if ($resp = $this->ensureMember($me)) {
            return $resp;
        }
        if ($resp = $this->checkContact($me, $contactId)) {
            return $resp;
        }
        return $this->successResponse('OK', $this->contactSettings(
            ContactSetting::of($me->caregiver_id, $contactId)));
    }

    /* Change any of: is_favorite, is_blocked, is_muted, and the background
       (background_type none/color/gradient, with background_value). A
       picture background is uploaded with background() instead. */
    public function update(Request $request, string $contactId): JsonResponse
    {
        $me = $request->get('auth_caregiver');
        if ($resp = $this->ensureMember($me)) {
            return $resp;
        }
        if ($resp = $this->checkContact($me, $contactId)) {
            return $resp;
        }

        $validator = Validator::make($request->all(), [
            'is_favorite'      => 'sometimes|boolean',
            'is_blocked'       => 'sometimes|boolean',
            'is_muted'         => 'sometimes|boolean',
            'background_type'  => 'sometimes|in:none,color,gradient',
            'background_value' => [
                'nullable',
                'required_if:background_type,color,gradient',
                'string',
                // #RRGGBB for a colour, a lowercase name for a gradient.
                $request->input('background_type') === 'color'
                    ? 'regex:/^#[0-9A-Fa-f]{6}$/'
                    : 'regex:/^[a-z_]{1,30}$/',
            ],
        ]);
        if ($validator->fails()) {
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $settings = ContactSetting::of($me->caregiver_id, $contactId);
        foreach (['is_favorite', 'is_blocked', 'is_muted'] as $flag) {
            if ($request->has($flag)) {
                $settings->{$flag} = $request->boolean($flag);
            }
        }
        if ($request->has('background_type')) {
            $type = $request->input('background_type');
            $settings->background_type = $type;
            $settings->background_value = $type === 'none'
                ? null
                : $request->input('background_value');
        }
        $settings->save();

        $this->logEvent('Contacts', 'settings updated', [
            'contact_id' => $contactId,
            'changed'    => array_keys($request->only([
                'is_favorite', 'is_blocked', 'is_muted', 'background_type',
            ])),
        ]);
        return $this->successResponse('Saved', $this->contactSettings($settings));
    }

    // Upload a picture to use as this contact's chat background.
    public function background(Request $request, string $contactId): JsonResponse
    {
        $me = $request->get('auth_caregiver');
        if ($resp = $this->ensureMember($me)) {
            return $resp;
        }
        if ($resp = $this->checkContact($me, $contactId)) {
            return $resp;
        }
        $validator = Validator::make($request->all(), [
            'image' => 'required|image|max:8192',
        ]);
        if ($validator->fails()) {
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $path = 'storage/' . $request->file('image')->store('uploads/chat_backgrounds', 'public');
        $settings = ContactSetting::of($me->caregiver_id, $contactId);
        $settings->background_type = 'image';
        $settings->background_value = $path;
        $settings->save();

        return $this->successResponse('Background saved', $this->contactSettings($settings));
    }

    public function favorites(Request $request): JsonResponse
    {
        return $this->listWhere($request, 'is_favorite');
    }

    public function blocked(Request $request): JsonResponse
    {
        return $this->listWhere($request, 'is_blocked');
    }

    // The people I've set [flag] on, by name, each with my settings.
    private function listWhere(Request $request, string $flag): JsonResponse
    {
        $me = $request->get('auth_caregiver');
        if ($resp = $this->ensureMember($me)) {
            return $resp;
        }
        $rows = ContactSetting::where('caregiver_id', $me->caregiver_id)
            ->where($flag, true)
            ->get()
            ->keyBy('contact_id');
        $people = Caregiver::whereIn('caregiver_id', $rows->keys())
            ->orderBy('name')
            ->get()
            ->map(fn ($c) => [
                'caregiver_id' => $c->caregiver_id,
                'name'         => $c->name,
                'avatar_emoji' => $c->avatar_emoji,
                'avatar_color' => $c->avatar_color,
                'settings'     => $this->contactSettings($rows[$c->caregiver_id]),
            ])
            ->values();
        return $this->successResponse('OK', $people);
    }

    // Settings can only be kept for another community member.
    private function checkContact(Caregiver $me, string $contactId): ?JsonResponse
    {
        if ($contactId === $me->caregiver_id) {
            return $this->errorResponse('That is you', 'INVALID_TARGET', 422);
        }
        $exists = Caregiver::where('caregiver_id', $contactId)
            ->where('is_community_member', true)
            ->exists();
        return $exists ? null : $this->errorResponse('Person not found', 'NOT_FOUND', 404);
    }
}
