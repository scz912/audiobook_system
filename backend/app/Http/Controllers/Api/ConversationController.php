<?php

namespace App\Http\Controllers\Api;

use App\Models\Caregiver;
use App\Models\Conversation;
use App\Models\ConversationParticipant;
use App\Models\Message;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class ConversationController extends ApiController
{
    // My conversations, each with the other people, last message, and unread count.
    public function index(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        if ($resp = $this->ensureMember($caregiver)) {
            return $resp;
        }

        $myParts = ConversationParticipant::where('caregiver_id', $caregiver->caregiver_id)->get();
        $conversationIds = $myParts->pluck('conversation_id');

        $conversations = Conversation::whereIn('conversation_id', $conversationIds)->get()
            ->keyBy('conversation_id');

        $out = [];
        foreach ($myParts as $part) {
            $conv = $conversations[$part->conversation_id] ?? null;
            if (!$conv) {
                continue;
            }
            $out[] = $this->serializeConversation($conv, $part, $caregiver->caregiver_id);
        }

        // Newest activity first.
        usort($out, fn ($a, $b) => strcmp($b['last_activity'] ?? '', $a['last_activity'] ?? ''));
        return $this->successResponse('OK', $out);
    }

    // Start (or reuse) a one-to-one chat with a friend.
    public function direct(Request $request): JsonResponse
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

        $otherId = $request->input('caregiver_id');
        if ($otherId === $caregiver->caregiver_id) {
            return $this->errorResponse('Cannot message yourself', 'INVALID_TARGET', 422);
        }
        $other = Caregiver::where('caregiver_id', $otherId)
            ->where('is_community_member', true)
            ->first();
        if (!$other) {
            return $this->errorResponse('Person not found', 'NOT_FOUND', 404);
        }

        $existing = $this->findDirect($caregiver->caregiver_id, $otherId);
        if ($existing) {
            $part = ConversationParticipant::where('conversation_id', $existing->conversation_id)
                ->where('caregiver_id', $caregiver->caregiver_id)->first();
            return $this->successResponse('OK', $this->serializeConversation($existing, $part, $caregiver->caregiver_id));
        }

        $conv = Conversation::create([
            'type'       => 'direct',
            'created_by' => $caregiver->caregiver_id,
        ]);
        $this->addParticipant($conv->conversation_id, $caregiver->caregiver_id, 'admin');
        $this->addParticipant($conv->conversation_id, $otherId, 'member');

        $part = ConversationParticipant::where('conversation_id', $conv->conversation_id)
            ->where('caregiver_id', $caregiver->caregiver_id)->first();
        return $this->successResponse('Conversation started', $this->serializeConversation($conv, $part, $caregiver->caregiver_id));
    }

    // Create a group chat with a title and a list of members.
    public function group(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        if ($resp = $this->ensureMember($caregiver)) {
            return $resp;
        }

        $validator = Validator::make($request->all(), [
            'title'            => 'required|string|max:100',
            'participant_ids'  => 'required|array|min:1',
            'participant_ids.*' => 'uuid',
        ]);
        if ($validator->fails()) {
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $conv = Conversation::create([
            'type'       => 'group',
            'title'      => $request->input('title'),
            'created_by' => $caregiver->caregiver_id,
        ]);
        $this->addParticipant($conv->conversation_id, $caregiver->caregiver_id, 'admin');

        $ids = collect($request->input('participant_ids'))
            ->unique()
            ->reject(fn ($id) => $id === $caregiver->caregiver_id);
        $members = Caregiver::whereIn('caregiver_id', $ids)
            ->where('is_community_member', true)
            ->pluck('caregiver_id');
        foreach ($members as $id) {
            $this->addParticipant($conv->conversation_id, $id, 'member');
        }

        $part = ConversationParticipant::where('conversation_id', $conv->conversation_id)
            ->where('caregiver_id', $caregiver->caregiver_id)->first();
        $this->logEvent('Chat', 'group created', ['conversation_id' => $conv->conversation_id]);
        return $this->successResponse('Group created', $this->serializeConversation($conv, $part, $caregiver->caregiver_id));
    }

    // Messages of a conversation (oldest first). Marks it read.
    public function messages(Request $request, string $conversationId): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $part = $this->myPart($conversationId, $caregiver->caregiver_id);
        if (!$part) {
            return $this->errorResponse('Conversation not found', 'NOT_FOUND', 404);
        }

        $rows = Message::where('conversation_id', $conversationId)
            ->orderBy('created_at')
            ->limit(200)
            ->get();
        // Load each sender once so group messages can show name + avatar.
        $senders = Caregiver::whereIn('caregiver_id', $rows->pluck('sender_id')->unique())
            ->get()->keyBy('caregiver_id');
        $messages = $rows->map(fn ($m) => $this->serializeMessage(
            $m,
            $caregiver->caregiver_id,
            $senders[$m->sender_id] ?? null,
        ));

        // Reading the thread clears the unread badge.
        $part->last_read_at = now();
        $part->save();

        return $this->successResponse('OK', $messages);
    }

    // Send a message into a conversation.
    public function send(Request $request, string $conversationId): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $part = $this->myPart($conversationId, $caregiver->caregiver_id);
        if (!$part) {
            return $this->errorResponse('Conversation not found', 'NOT_FOUND', 404);
        }

        $validator = Validator::make($request->all(), [
            'body' => 'required|string|max:2000',
        ]);
        if ($validator->fails()) {
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $message = Message::create([
            'conversation_id' => $conversationId,
            'sender_id'       => $caregiver->caregiver_id,
            'body'            => trim($request->input('body')),
        ]);

        // The sender has by definition read their own message.
        $part->last_read_at = now();
        $part->save();

        return $this->successResponse('Sent', $this->serializeMessage($message, $caregiver->caregiver_id, $caregiver));
    }

    // Mark a conversation as read without loading it.
    public function markRead(Request $request, string $conversationId): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $part = $this->myPart($conversationId, $caregiver->caregiver_id);
        if (!$part) {
            return $this->errorResponse('Conversation not found', 'NOT_FOUND', 404);
        }
        $part->last_read_at = now();
        $part->save();
        return $this->successResponse('OK');
    }

    // My participant row for a conversation, or null if I'm not in it.
    private function myPart(string $conversationId, string $caregiverId): ?ConversationParticipant
    {
        return ConversationParticipant::where('conversation_id', $conversationId)
            ->where('caregiver_id', $caregiverId)
            ->first();
    }

    private function addParticipant(string $conversationId, string $caregiverId, string $role): void
    {
        ConversationParticipant::firstOrCreate(
            ['conversation_id' => $conversationId, 'caregiver_id' => $caregiverId],
            ['role' => $role]
        );
    }

    // Find an existing direct chat that has exactly these two people.
    private function findDirect(string $a, string $b): ?Conversation
    {
        $aConvs = ConversationParticipant::where('caregiver_id', $a)->pluck('conversation_id');
        $bConvs = ConversationParticipant::where('caregiver_id', $b)->pluck('conversation_id');
        $shared = $aConvs->intersect($bConvs);
        if ($shared->isEmpty()) {
            return null;
        }
        return Conversation::whereIn('conversation_id', $shared)
            ->where('type', 'direct')
            ->first();
    }

    private function serializeConversation(Conversation $conv, ?ConversationParticipant $myPart, string $meId): array
    {
        $others = ConversationParticipant::where('conversation_id', $conv->conversation_id)
            ->where('caregiver_id', '!=', $meId)
            ->get();
        $otherPeople = Caregiver::whereIn('caregiver_id', $others->pluck('caregiver_id'))->get()
            ->map(fn ($c) => [
                'caregiver_id' => $c->caregiver_id,
                'name'         => $c->name,
                'avatar_emoji' => $c->avatar_emoji,
                'avatar_color' => $c->avatar_color,
            ])->values();

        $last = Message::where('conversation_id', $conv->conversation_id)
            ->orderByDesc('created_at')->first();

        $unread = 0;
        if ($myPart) {
            $q = Message::where('conversation_id', $conv->conversation_id)
                ->where('sender_id', '!=', $meId);
            if ($myPart->last_read_at) {
                $q->where('created_at', '>', $myPart->last_read_at);
            }
            $unread = $q->count();
        }

        $title = $conv->type === 'group'
            ? $conv->title
            : ($otherPeople[0]['name'] ?? 'Chat');

        return [
            'conversation_id' => $conv->conversation_id,
            'type'            => $conv->type,
            'title'           => $title,
            'participants'    => $otherPeople,
            'last_message'    => $last ? [
                'body'      => $last->body,
                'sender_id' => $last->sender_id,
                'sent_at'   => $last->created_at?->toIso8601String(),
            ] : null,
            'unread_count'    => $unread,
            'last_activity'   => ($last?->created_at ?? $conv->created_at)?->toIso8601String(),
        ];
    }

    private function serializeMessage(Message $m, string $meId, ?Caregiver $sender = null): array
    {
        return [
            'message_id'      => $m->message_id,
            'conversation_id' => $m->conversation_id,
            'sender_id'       => $m->sender_id,
            'body'            => $m->body,
            'is_mine'         => $m->sender_id === $meId,
            'sent_at'         => $m->created_at?->toIso8601String(),
            'sender'          => $sender ? [
                'caregiver_id' => $sender->caregiver_id,
                'name'         => $sender->name,
                'avatar_emoji' => $sender->avatar_emoji,
                'avatar_color' => $sender->avatar_color,
            ] : null,
        ];
    }
}
