<?php

namespace App\Http\Controllers\Api;

use App\Models\MusicTasteCount;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

/* The child's YouTube genre counts, kept online (music_taste_counts).

   sync: the phone sends every day it still holds, from [from] to today,
   with plays per genre. Those days are replaced as a whole, so sending the
   same days again never double-counts. Days before [from] (the phone has
   already forgotten them) stay as they were. */
class MusicTasteController extends ApiController
{
    public function sync(Request $request, string $childId): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $profile = $caregiver?->childProfiles()->where('child_id', $childId)->first();
        if (!$profile) {
            return $this->errorResponse('Child profile not found', 'NOT_FOUND', 404);
        }

        $validator = Validator::make($request->all(), [
            'from'           => 'required|date_format:Y-m-d',
            'counts'         => 'present|array|max:2000',
            'counts.*.day'   => 'required|date_format:Y-m-d|after_or_equal:from',
            'counts.*.genre' => 'required|string|max:60',
            'counts.*.plays' => 'required|integer|min:1|max:100000',
        ]);
        if ($validator->fails()) {
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $from = $request->input('from');
        // One row per (day, genre), even if the phone sent one twice.
        $rows = [];
        foreach ($request->input('counts') as $c) {
            $key = $c['day'] . '|' . $c['genre'];
            $rows[$key] = [
                'child_id'   => $profile->child_id,
                'day'        => $c['day'],
                'genre'      => $c['genre'],
                'plays'      => (int) $c['plays'],
                'created_at' => now(),
                'updated_at' => now(),
            ];
        }

        DB::transaction(function () use ($profile, $from, $rows) {
            MusicTasteCount::where('child_id', $profile->child_id)
                ->where('day', '>=', $from)
                ->delete();
            foreach (array_chunk(array_values($rows), 500) as $chunk) {
                MusicTasteCount::insert($chunk);
            }
        });

        $this->logEvent('MusicTaste', 'sync', [
            'child_id' => $profile->child_id,
            'from'     => $from,
            'rows'     => count($rows),
        ]);
        return $this->successResponse('Music taste saved', ['rows' => count($rows)]);
    }
}
