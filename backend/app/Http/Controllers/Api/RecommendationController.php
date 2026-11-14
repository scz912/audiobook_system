<?php

namespace App\Http\Controllers\Api;

use App\Models\Audiobook;
use App\Models\ListeningHistory;
use App\Models\MusicTrack;
use App\Services\BookRecommender;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

/* "Recommended for you": audiobooks picked for one child by
   BookRecommender, from the family's library. */
class RecommendationController extends ApiController
{
    private const TZ = 'Asia/Kuala_Lumpur';

    public function forChild(Request $request, string $childId): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $profile = $caregiver?->childProfiles()->where('child_id', $childId)->first();
        if (!$profile) {
            return $this->errorResponse('Child profile not found', 'NOT_FOUND', 404);
        }

        $validator = Validator::make($request->all(), [
            'mood'    => 'nullable|in:happy,calm,curious,sleepy',
            'limit'   => 'nullable|integer|min:1|max:10',
            // Optional music taste: background-music genre => 0..1.
            'taste'   => 'nullable|array|max:20',
            'taste.*' => 'numeric|min:0|max:1',
        ]);
        if ($validator->fails()) {
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $now = Carbon::now(self::TZ);

        // Candidates: this family's library.
        $library = Audiobook::visibleTo($caregiver->caregiver_id)->get();
        $tracks = MusicTrack::whereIn('track_id', $library->pluck('track_id')->filter()->unique())
            ->get()->keyBy('track_id');
        $books = $library->map(fn (Audiobook $b) => [
            'id'         => $b->audiobook_id,
            // Starter books are copies per family; match them by the original.
            'canon'      => $b->source_audiobook_id ?: $b->audiobook_id,
            'title'      => $b->title,
            'category'   => $b->category,
            'topic'      => $b->topic,
            'tags'       => $b->tags,
            'difficulty' => $b->difficulty,
            'format'     => $b->book_format ?? 'linear',
            'language'   => $b->language,
            'age_group'  => $b->age_group,
            'status'     => $b->status,
            'genre'      => $tracks[$b->track_id]->genre ?? null,
            'emotions'   => isset($tracks[$b->track_id]) ? $tracks[$b->track_id]->tagsArray() : [],
        ])->values()->all();

        // Everyone's recent listening (for "children who liked this...").
        $history = ListeningHistory::where('created_at', '>=', $now->copy()->subDays(BookRecommender::WINDOW_DAYS))
            ->get(['child_id', 'audiobook_id', 'completed', 'pages_total', 'pages_reached', 'mood', 'created_at']);
        $canonOf = Audiobook::whereIn('audiobook_id', $history->pluck('audiobook_id')->unique())
            ->get(['audiobook_id', 'source_audiobook_id'])
            ->mapWithKeys(fn ($b) => [$b->audiobook_id => $b->source_audiobook_id ?: $b->audiobook_id]);
        $sessions = $history->filter(fn ($s) => isset($canonOf[$s->audiobook_id]))
            ->map(fn ($s) => [
                'child'     => $s->child_id,
                'canon'     => $canonOf[$s->audiobook_id],
                'completed' => (bool) $s->completed,
                'progress'  => $s->pages_total ? min(1.0, (int) $s->pages_reached / (int) $s->pages_total) : null,
                'at'        => Carbon::parse($s->created_at),
            ])->values()->all();

        // Today's mood: as sent, else the latest picked today.
        $mood = $request->input('mood') ?: $history
            ->where('child_id', $profile->child_id)
            ->filter(fn ($s) => $s->mood && Carbon::parse($s->created_at)->setTimezone(self::TZ)->isSameDay($now))
            ->sortByDesc('created_at')
            ->first()?->mood;

        $items = app(BookRecommender::class)->recommend($books, $sessions, [
            'child' => $profile->child_id,
            'age'   => $profile->age,
            'mood'  => $mood,
            'taste' => array_map('floatval', (array) $request->input('taste', [])),
            'limit' => (int) $request->input('limit', 3),
        ], $now);

        $this->logEvent('Recommend', 'forChild', [
            'child_id'   => $profile->child_id,
            'candidates' => count($books),
            'returned'   => count($items),
            'mood'       => $mood,
        ]);
        return $this->successResponse('OK', ['mood' => $mood, 'items' => $items]);
    }
}
