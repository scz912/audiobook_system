<?php

namespace App\Http\Controllers\Api;

use App\Models\MusicTrack;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MusicTrackController extends ApiController
{
    /* List active music tracks. Can filter by tags and search by title.
       A track must have all the chosen tags to show. */
    public function list(Request $request): JsonResponse
    {
        $this->logEvent('MusicTrack', 'list called', [
            'tags'   => $request->input('tags'),
            'search' => $request->input('search'),
        ]);

        $tracks = MusicTrack::where('status', 'active')->get();

        // Keep only tracks that have every chosen tag.
        $filterTags = $request->input('tags', []);
        if (is_array($filterTags) && count($filterTags) > 0) {
            $tracks = $tracks->filter(function (MusicTrack $t) use ($filterTags) {
                $trackTags = array_map('strtolower', $t->tagsArray());
                foreach ($filterTags as $ft) {
                    if (!in_array(strtolower(trim($ft)), $trackTags, true)) {
                        return false;
                    }
                }
                return true;
            });
        }

        // Search by title or composer.
        $search = trim((string) $request->input('search', ''));
        if ($search !== '') {
            $lower = strtolower($search);
            $tracks = $tracks->filter(function (MusicTrack $t) use ($lower) {
                $label = strtolower($t->title . '-' . $t->composer);
                return str_contains($label, $lower);
            });
        }

        return $this->successResponse('OK', [
            'tracks' => $tracks->values()->map(fn ($t) => $this->serialize($t)),
        ]);
    }

    /* All the tags used on active tracks, sorted. Fills the filter chips
       in the picker. */
    public function allTags(): JsonResponse
    {
        $this->logEvent('MusicTrack', 'allTags called');

        $tags = MusicTrack::where('status', 'active')
            ->pluck('tags')
            ->flatMap(fn ($t) => array_map('trim', explode(',', $t)))
            ->filter()
            ->unique()
            ->sort()
            ->values();

        return $this->successResponse('OK', ['tags' => $tags]);
    }

    /* Given the tags already picked, return the other tags that can still
       be added (a track exists with all of them). Lets the picker hide
       tags that would give no results. */
    public function compatibleTags(Request $request): JsonResponse
    {
        $selected = $request->input('selected_tags', []);

        $active = MusicTrack::where('status', 'active')->get();

        // Tracks that match what's picked so far.
        $matching = $active->filter(function (MusicTrack $t) use ($selected) {
            $tt = array_map('strtolower', $t->tagsArray());
            foreach ($selected as $s) {
                if (!in_array(strtolower(trim($s)), $tt, true)) {
                    return false;
                }
            }
            return true;
        });

        // Tags on those tracks, minus the ones already picked.
        $selectedLower = array_map('strtolower', array_map('trim', $selected));

        $compatible = $matching
            ->flatMap(fn ($t) => $t->tagsArray())
            ->map(fn ($t) => trim($t))
            ->filter(fn ($t) => !in_array(strtolower($t), $selectedLower, true))
            ->unique()
            ->sort()
            ->values();

        return $this->successResponse('OK', ['tags' => $compatible]);
    }

    private function serialize(MusicTrack $t): array
    {
        return [
            'track_id'      => $t->track_id,
            'title'         => $t->title,
            'composer'      => $t->composer,
            'file_url'      => $this->mediaUrl($t->file_path),
            'tags'          => $t->tagsArray(),
            'tempo'         => $t->tempo,
            'duration_secs' => $t->duration_secs,
        ];
    }
}
