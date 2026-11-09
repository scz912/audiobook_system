<?php

namespace App\Services;

use App\Models\Audiobook;
use App\Models\MusicTrack;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/* The books every account starts with, so no library opens empty: three
   linear and three interactive books from the demo account. Each account
   gets its own private copy (like "Save a copy" from the hub), so a family
   can delete or change theirs without touching anyone else's.

   Linear books are picked by title. Interactive ones are the demo
   account's oldest finished interactive books. */
class StarterLibrary
{
    public const LINEAR_TITLES = [
        '3 Kids playing ball together',
        'A tree with emotion',
        'Rahsia di Sebalik Kulit Manggis',
    ];

    public const INTERACTIVE_COUNT = 3;

    /** The books to copy, oldest original first. Empty if none are found. */
    public static function sources(): Collection
    {
        $linear = collect(self::LINEAR_TITLES)
            ->map(fn (string $title) => self::finished()
                ->where('audiobooks.book_format', 'linear')
                ->whereRaw('LOWER(audiobooks.title) = ?', [mb_strtolower($title)])
                ->first())
            ->filter()
            ->values();

        // The demo account: whoever owns the first linear starter.
        $owner = $linear->first()?->caregiver_id;
        $interactive = $owner === null
            ? collect()
            : self::finished()
                ->where('audiobooks.book_format', 'interactive')
                ->where('audiobooks.caregiver_id', $owner)
                ->limit(self::INTERACTIVE_COUNT)
                ->get();

        return $linear->concat($interactive)->values();
    }

    /* Give [caregiverId] a copy of each starter they don't have yet. Safe to
       run again: a book they own, already copied, or with the same title
       and format (say, from an older migration) is skipped. Returns how
       many copies were made. */
    public static function giveTo(string $caregiverId, ?Collection $sources = null): int
    {
        $made = 0;
        foreach ($sources ?? self::sources() as $book) {
            if ($book->caregiver_id === $caregiverId) {
                continue;
            }
            $has = Audiobook::where('caregiver_id', $caregiverId)
                ->where(function ($q) use ($book) {
                    $q->where('source_audiobook_id', $book->audiobook_id)
                      ->orWhere(function ($q) use ($book) {
                          $q->whereRaw('LOWER(title) = ?', [mb_strtolower($book->title)])
                            ->where('book_format', $book->book_format);
                      });
                })
                ->exists();
            if ($has) {
                continue;
            }
            self::copy($book, $caregiverId);
            $made++;
        }
        return $made;
    }

    /* A private copy of [book] for [caregiverId], pages and all. The files
       (pictures, audio) are shared: deleting a book only removes its rows. */
    public static function copy(Audiobook $book, string $caregiverId): Audiobook
    {
        return DB::transaction(function () use ($book, $caregiverId) {
            $copy = $book->replicate(['caregiver_id', 'visibility', 'source_audiobook_id']);
            $copy->audiobook_id = (string) Str::uuid();
            $copy->caregiver_id = $caregiverId;
            $copy->visibility = 'private';
            $copy->source_audiobook_id = $book->audiobook_id;
            // Keep the background music only if it's one they can use too
            // (not someone's private upload).
            if ($copy->track_id && !MusicTrack::visibleTo($caregiverId)->where('track_id', $copy->track_id)->exists()) {
                $copy->track_id = null;
            }
            $copy->save();

            $pages = DB::table('audiobook_pages')
                ->where('audiobook_id', $book->audiobook_id)
                ->get()
                ->map(function ($page) use ($copy) {
                    $row = (array) $page;
                    $row['page_id'] = (string) Str::uuid();
                    $row['audiobook_id'] = $copy->audiobook_id;
                    return $row;
                })
                ->all();
            foreach (array_chunk($pages, 200) as $chunk) {
                DB::table('audiobook_pages')->insert($chunk);
            }
            return $copy;
        });
    }

    /* Finished originals (not copies, not still making pictures), oldest
       first. Older migrations copied rows whole, so a title can have many
       rows with the same date: the oldest account's comes first. */
    private static function finished()
    {
        return Audiobook::query()
            ->select('audiobooks.*')
            ->join('caregivers', 'caregivers.caregiver_id', '=', 'audiobooks.caregiver_id')
            ->whereNull('audiobooks.source_audiobook_id')
            ->where(function ($q) {
                $q->whereNull('audiobooks.status')->orWhere('audiobooks.status', '!=', 'processing');
            })
            ->orderBy('audiobooks.created_at')
            ->orderBy('caregivers.created_at');
    }
}
