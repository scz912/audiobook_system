<?php

namespace App\Http\Controllers\Api;

use App\Models\CommunityInvite;
use App\Models\Friendship;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class InviteController extends ApiController
{
    // Whether the current caregiver has joined the community yet.
    public function status(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        return $this->successResponse('OK', [
            'is_member' => (bool) $caregiver->is_community_member,
            'profile'   => $this->serializeProfile($caregiver),
        ]);
    }

    /* Join the community. Every registered caregiver is a verified family of
       an autistic child, so joining is opt-in. The hub still stays private
       because only signed-in members can ever see it. */
    public function join(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $caregiver->is_community_member = true;
        $caregiver->save();
        $this->logEvent('Community', 'joined', ['caregiver_id' => $caregiver->caregiver_id]);
        return $this->successResponse('Welcome to the community', [
            'is_member' => true,
        ]);
    }

    // Make an invite code the caregiver can share with another family.
    public function create(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        if ($resp = $this->ensureMember($caregiver)) {
            return $resp;
        }

        $validator = Validator::make($request->all(), [
            'email' => 'nullable|email|max:255',
        ]);
        if ($validator->fails()) {
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        // A short, easy-to-share code. Loop on the tiny chance it collides.
        do {
            $code = strtoupper(Str::random(8));
        } while (CommunityInvite::where('code', $code)->exists());

        $invite = CommunityInvite::create([
            'inviter_id' => $caregiver->caregiver_id,
            'code'       => $code,
            'email'      => $request->input('email'),
            'status'     => 'pending',
        ]);

        $this->logEvent('Community', 'invite created', [
            'caregiver_id' => $caregiver->caregiver_id,
            'invite_id'    => $invite->invite_id,
        ]);
        return $this->successResponse('Invite created', $this->serializeInvite($invite));
    }

    // Invites the current caregiver has sent.
    public function myInvites(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $invites = CommunityInvite::where('inviter_id', $caregiver->caregiver_id)
            ->orderByDesc('created_at')
            ->get()
            ->map(fn ($i) => $this->serializeInvite($i));
        return $this->successResponse('OK', $invites);
    }

    /* Redeem an invite code. The caregiver becomes a member and is auto-
       friended with whoever invited them. */
    public function accept(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');

        $validator = Validator::make($request->all(), [
            'code' => 'required|string|max:12',
        ]);
        if ($validator->fails()) {
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $code = strtoupper(trim($request->input('code')));
        $invite = CommunityInvite::where('code', $code)->first();
        if (!$invite) {
            return $this->errorResponse('Invite code not found', 'INVITE_NOT_FOUND', 404);
        }
        if ($invite->status !== 'pending') {
            return $this->errorResponse('This invite was already used', 'INVITE_USED', 409);
        }
        if ($invite->inviter_id === $caregiver->caregiver_id) {
            return $this->errorResponse('You cannot accept your own invite', 'OWN_INVITE', 422);
        }

        $invite->status = 'accepted';
        $invite->accepted_by = $caregiver->caregiver_id;
        $invite->save();

        $caregiver->is_community_member = true;
        $caregiver->save();

        $this->linkAsFriends($invite->inviter_id, $caregiver->caregiver_id);

        $this->logEvent('Community', 'invite accepted', [
            'invite_id'   => $invite->invite_id,
            'accepted_by' => $caregiver->caregiver_id,
        ]);
        return $this->successResponse('You joined the community', [
            'is_member' => true,
        ]);
    }

    // Make an accepted friendship between two caregivers if none exists.
    private function linkAsFriends(string $a, string $b): void
    {
        $existing = Friendship::where(function ($q) use ($a, $b) {
            $q->where('requester_id', $a)->where('addressee_id', $b);
        })->orWhere(function ($q) use ($a, $b) {
            $q->where('requester_id', $b)->where('addressee_id', $a);
        })->first();

        if ($existing) {
            if ($existing->status === 'pending') {
                $existing->status = 'accepted';
                $existing->save();
            }
            return;
        }

        Friendship::create([
            'requester_id' => $a,
            'addressee_id' => $b,
            'status'       => 'accepted',
        ]);
    }

    private function serializeInvite(CommunityInvite $invite): array
    {
        return [
            'invite_id'  => $invite->invite_id,
            'code'       => $invite->code,
            'email'      => $invite->email,
            'status'     => $invite->status,
            'created_at' => $invite->created_at?->toIso8601String(),
        ];
    }

    private function serializeProfile($caregiver): array
    {
        return [
            'caregiver_id' => $caregiver->caregiver_id,
            'name'         => $caregiver->name,
            'bio'          => $caregiver->bio,
            'avatar_emoji' => $caregiver->avatar_emoji,
            'avatar_color' => $caregiver->avatar_color,
        ];
    }
}
