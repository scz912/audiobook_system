<?php

namespace App\Http\Controllers\Api;

use App\Models\ChildProfile;
use App\Models\ListeningHistory;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class ListeningHistoryController extends ApiController
{
    public function record(Request $request): JsonResponse
    {
        $this->logEvent('History', 'record called', [
            'child_id'         => $request->input('child_id'),
            'audiobook_id'     => $request->input('audiobook_id'),
            'duration_seconds' => $request->input('duration_seconds'),
            'completed'        => $request->input('completed'),
            'mood'             => $request->input('mood'),
            'pause_count'      => $request->input('pause_count'),
            'skip_count'       => $request->input('skip_count'),
        ]);

        $validator = Validator::make($request->all(), [
            'child_id'              => 'required|string|uuid',
            'audiobook_id'          => 'required|string|uuid',
            'duration_seconds'      => 'nullable|integer|min:0',
            'last_position_seconds' => 'nullable|integer|min:0',
            'mood'                  => 'nullable|in:happy,calm,curious,sleepy',
            'completed'             => 'nullable|boolean',
            'pause_count'           => 'nullable|integer|min:0',
            'skip_count'            => 'nullable|integer|min:0',
        ]);

        if ($validator->fails()) {
            $this->logWarn('History', 'record validation failed', [
                'errors' => $validator->errors()->all(),
            ]);
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $caregiver = $request->get('auth_caregiver');
        $profile = ChildProfile::where('child_id', $request->input('child_id'))
            ->where('caregiver_id', $caregiver->caregiver_id)
            ->first();
        if (!$profile) {
            $this->logWarn('History', 'record child not found', [
                'child_id'     => $request->input('child_id'),
                'caregiver_id' => $caregiver->caregiver_id,
            ]);
            return $this->errorResponse('Child profile not found', 'NOT_FOUND', 404);
        }

        $history = ListeningHistory::create($validator->validated());
        $this->logEvent('History', 'record success', [
            'history_id'  => $history->history_id,
            'child_id'    => $history->child_id,
            'mood'        => $history->mood,
            'pause_count' => (int) $history->pause_count,
            'skip_count'  => (int) $history->skip_count,
        ]);

        // Bump the running total for this child.
        if ($request->filled('duration_seconds')) {
            $profile->increment(
                'listening_minutes',
                (int) round(((int) $request->input('duration_seconds')) / 60)
            );
        }

        return $this->successResponse('Listening session recorded', [
            'history_id'            => $history->history_id,
            'child_id'              => $history->child_id,
            'audiobook_id'          => $history->audiobook_id,
            'duration_seconds'      => $history->duration_seconds,
            'last_position_seconds' => $history->last_position_seconds,
            'mood'                  => $history->mood,
            'completed'             => (bool) $history->completed,
            'pause_count'           => (int) $history->pause_count,
            'skip_count'            => (int) $history->skip_count,
        ]);
    }

    public function forProfile(Request $request, string $childId): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $this->logEvent('History', 'forProfile called', [
            'caregiver_id' => $caregiver->caregiver_id,
            'child_id'     => $childId,
        ]);
        $profile = ChildProfile::where('child_id', $childId)
            ->where('caregiver_id', $caregiver->caregiver_id)
            ->first();
        if (!$profile) {
            $this->logWarn('History', 'forProfile child not found', [
                'child_id' => $childId,
            ]);
            return $this->errorResponse('Child profile not found', 'NOT_FOUND', 404);
        }

        $history = $profile->listeningHistory()
            ->orderByDesc('created_at')
            ->limit(50)
            ->get()
            ->map(fn ($h) => [
                'history_id'            => $h->history_id,
                'audiobook_id'          => $h->audiobook_id,
                'duration_seconds'      => $h->duration_seconds,
                'last_position_seconds' => $h->last_position_seconds,
                'mood'                  => $h->mood,
                'completed'             => (bool) $h->completed,
                'pause_count'           => (int) $h->pause_count,
                'skip_count'            => (int) $h->skip_count,
                'created_at'            => $h->created_at?->format('Y-m-d H:i:s'),
            ]);

        return $this->successResponse('OK', $history);
    }
}
