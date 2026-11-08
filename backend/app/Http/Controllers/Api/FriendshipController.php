<?php

namespace App\Http\Controllers\Api;

use App\Models\Caregiver;
use App\Models\Conversation;
use App\Models\Friendship;
use App\Models\HubPost;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class FriendshipController extends ApiController
{
    // Find other community members by name or email.
    public function search(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        if ($resp = $this->ensureMember($caregiver)) {
            return $resp;
        }

        $term = trim((string) $request->input('search', ''));
        $query = Caregiver::where('is_community_member', true)
            ->where('caregiver_id', '!=', $caregiver->caregiver_id);

        if ($term !== '') {
            $like = '%' . $term . '%';
            $query->where(function ($q) use ($like) {
                $q->where('name', 'like', $like)->orWhere('email', 'like', $like);
            });
        }

        $people = $query->orderBy('name')->limit(30)->get()
            ->map(fn ($c) => $this->serializePerson($c, $caregiver->caregiver_id));
        return $this->successResponse('OK', $people);
    }

    // Send a friend request to another member.
    public function requestFriend(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        if ($resp = $this->ensureMember($caregiver)) {
            return $resp;
        }

        $validator = Validator::make($request->all(), [
            'caregiver_id' => 'required|uuid',
        ]);
        if ($validator->fails()) {
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $targetId = $request->input('caregiver_id');
        if ($targetId === $caregiver->caregiver_id) {
            return $this->errorResponse('You cannot friend yourself', 'INVALID_TARGET', 422);
        }
        $target = Caregiver::where('caregiver_id', $targetId)
            ->where('is_community_member', true)
            ->first();
        if (!$target) {
            return $this->errorResponse('Person not found', 'NOT_FOUND', 404);
        }

        $existing = $this->between($caregiver->caregiver_id, $targetId);
        // A declined request doesn't block asking again.
        if ($existing && $existing->status === 'declined') {
            $existing->delete();
            $existing = null;
        }
        if ($existing) {
            return $this->errorResponse('A request already exists', 'ALREADY_EXISTS', 409);
        }

        $friendship = Friendship::create([
            'requester_id' => $caregiver->caregiver_id,
            'addressee_id' => $targetId,
            'status'       => 'pending',
        ]);
        $this->logEvent('Friendship', 'request sent', [
            'friendship_id' => $friendship->friendship_id,
        ]);
        return $this->successResponse('Request sent', ['status' => 'pending']);
    }

    // Accept or decline a request that was sent to me.
    public function respond(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');

        $validator = Validator::make($request->all(), [
            'friendship_id' => 'required|uuid',
            'action'        => 'required|in:accept,decline',
        ]);
        if ($validator->fails()) {
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $friendship = Friendship::where('friendship_id', $request->input('friendship_id'))
            ->where('addressee_id', $caregiver->caregiver_id)
            ->where('status', 'pending')
            ->first();
        if (!$friendship) {
            return $this->errorResponse('Request not found', 'NOT_FOUND', 404);
        }

        // Either way the sender gets a red dot until they've seen the answer.
        $accepted = $request->input('action') === 'accept';
        $friendship->status = $accepted ? 'accepted' : 'declined';
        $friendship->requester_seen = false;
        $friendship->save();

        // New friends can message each other straight from the Chat tab.
        if ($accepted) {
            Conversation::openDirect($friendship->requester_id, $friendship->addressee_id);
        }

        return $accepted
            ? $this->successResponse('You are now friends', ['status' => 'accepted'])
            : $this->successResponse('Request declined', ['status' => 'declined']);
    }

    // Answers to requests I sent that I haven't seen yet.
    public function updates(Request $request): JsonResponse
    {
        $me = $request->get('auth_caregiver')->caregiver_id;
        $rows = Friendship::where('requester_id', $me)
            ->where('requester_seen', false)
            ->whereIn('status', ['accepted', 'declined'])
            ->orderByDesc('updated_at')
            ->get();

        $out = $rows->map(function ($f) {
            $person = Caregiver::where('caregiver_id', $f->addressee_id)->first();
            return [
                'friendship_id' => $f->friendship_id,
                'status'        => $f->status,
                'person'        => $person ? $this->serializeBasic($person) : null,
            ];
        })->filter(fn ($r) => $r['person'] !== null)->values();
        return $this->successResponse('OK', $out);
    }

    /* I've seen the answers. Accepted ones are just marked read; declined
       ones are removed, so we can ask each other again later. */
    public function markUpdatesSeen(Request $request): JsonResponse
    {
        $me = $request->get('auth_caregiver')->caregiver_id;
        $unseen = Friendship::where('requester_id', $me)->where('requester_seen', false);
        (clone $unseen)->where('status', 'declined')->delete();
        $unseen->update(['requester_seen' => true]);
        return $this->successResponse('OK');
    }

    // Remove a friend or cancel a request I sent.
    public function remove(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');

        $validator = Validator::make($request->all(), [
            'caregiver_id' => 'required|uuid',
        ]);
        if ($validator->fails()) {
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $friendship = $this->between($caregiver->caregiver_id, $request->input('caregiver_id'));
        if (!$friendship) {
            return $this->errorResponse('Not found', 'NOT_FOUND', 404);
        }
        $friendship->delete();
        return $this->successResponse('Removed');
    }

    // My accepted friends.
    public function friends(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $me = $caregiver->caregiver_id;

        $rows = Friendship::where('status', 'accepted')
            ->where(function ($q) use ($me) {
                $q->where('requester_id', $me)->orWhere('addressee_id', $me);
            })
            ->get();

        $friendIds = $rows->map(fn ($f) => $f->requester_id === $me ? $f->addressee_id : $f->requester_id);
        $friends = Caregiver::whereIn('caregiver_id', $friendIds)->orderBy('name')->get()
            ->map(fn ($c) => $this->serializePerson($c, $me));
        return $this->successResponse('OK', $friends);
    }

    // Pending requests other people sent to me.
    public function pending(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $rows = Friendship::where('addressee_id', $caregiver->caregiver_id)
            ->where('status', 'pending')
            ->orderByDesc('created_at')
            ->get();

        $out = $rows->map(function ($f) {
            $person = Caregiver::where('caregiver_id', $f->requester_id)->first();
            return [
                'friendship_id' => $f->friendship_id,
                'person'        => $person ? $this->serializeBasic($person) : null,
            ];
        })->filter(fn ($r) => $r['person'] !== null)->values();
        return $this->successResponse('OK', $out);
    }

    // A member's public profile plus how many books they've shared.
    public function profile(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        if ($resp = $this->ensureMember($caregiver)) {
            return $resp;
        }

        $validator = Validator::make($request->all(), [
            'caregiver_id' => 'required|uuid',
        ]);
        if ($validator->fails()) {
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $person = Caregiver::where('caregiver_id', $request->input('caregiver_id'))
            ->where('is_community_member', true)
            ->first();
        if (!$person) {
            return $this->errorResponse('Person not found', 'NOT_FOUND', 404);
        }

        $data = $this->serializePerson($person, $caregiver->caregiver_id);
        $data['shared_count'] = HubPost::where('shared_by', $person->caregiver_id)->count();
        return $this->successResponse('OK', $data);
    }

    // The friendship row between two people, in either direction.
    private function between(string $a, string $b): ?Friendship
    {
        return Friendship::where(function ($q) use ($a, $b) {
            $q->where('requester_id', $a)->where('addressee_id', $b);
        })->orWhere(function ($q) use ($a, $b) {
            $q->where('requester_id', $b)->where('addressee_id', $a);
        })->first();
    }

    private function serializeBasic($c): array
    {
        return [
            'caregiver_id' => $c->caregiver_id,
            'name'         => $c->name,
            'avatar_emoji' => $c->avatar_emoji,
            'avatar_color' => $c->avatar_color,
        ];
    }

    // Basic profile plus this viewer's relationship to the person.
    private function serializePerson($c, string $viewerId): array
    {
        $link = $this->between($viewerId, $c->caregiver_id);
        $relation = 'none';
        if ($link) {
            if ($link->status === 'accepted') {
                $relation = 'friends';
            } elseif ($link->status === 'pending') {
                $relation = $link->requester_id === $viewerId ? 'request_sent' : 'request_received';
            } elseif ($link->status === 'blocked') {
                $relation = 'blocked';
            }
            // 'declined' reads as 'none': either side may ask again.
        }

        return [
            'caregiver_id'  => $c->caregiver_id,
            'name'          => $c->name,
            'bio'           => $c->bio,
            'avatar_emoji'  => $c->avatar_emoji,
            'avatar_color'  => $c->avatar_color,
            'relation'      => $relation,
            'friendship_id' => $link?->friendship_id,
        ];
    }
}
