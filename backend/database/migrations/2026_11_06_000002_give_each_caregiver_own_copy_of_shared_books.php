<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/* Books made before books had owners have no caregiver_id. Every caregiver
   sees them and every caregiver can edit them, so one caregiver deleting one
   deleted it for every family.

   This gives each caregiver their own private copy of every such book, as
   if they had made it themselves:
   - One caregiver keeps the original row: the first one who shared it in
     the hub (so the hub post, likes and comments stay put), otherwise the
     oldest account.
   - Everyone else gets a copy with its own pages. Their children's
     listening history and their own hub posts of that book move to the copy.

   Copies point at the same image/audio files as the original. That's safe
   because deleting a book only removes its database rows, not its files. */
return new class extends Migration
{
    public function up(): void
    {
        $caregiverIds = DB::table('caregivers')
            ->orderBy('created_at')
            ->orderBy('caregiver_id')
            ->pluck('caregiver_id')
            ->all();

        // No accounts yet: nobody to give the books to, leave them shared.
        if (empty($caregiverIds)) {
            return;
        }

        $childrenOf = DB::table('child_profiles')
            ->select('child_id', 'caregiver_id')
            ->get()
            ->groupBy('caregiver_id')
            ->map(fn ($rows) => $rows->pluck('child_id')->all());

        $sharedBookIds = DB::table('audiobooks')
            ->whereNull('caregiver_id')
            ->pluck('audiobook_id');

        foreach ($sharedBookIds as $bookId) {
            DB::transaction(function () use ($bookId, $caregiverIds, $childrenOf) {
                $book = DB::table('audiobooks')->where('audiobook_id', $bookId)->first();
                if (!$book || $book->caregiver_id !== null) {
                    return;
                }

                $keeper = DB::table('hub_posts')
                    ->where('audiobook_id', $bookId)
                    ->whereIn('shared_by', $caregiverIds)
                    ->orderBy('created_at')
                    ->value('shared_by') ?? $caregiverIds[0];

                $pages = DB::table('audiobook_pages')
                    ->where('audiobook_id', $bookId)
                    ->get();

                foreach ($caregiverIds as $caregiverId) {
                    if ($caregiverId === $keeper) {
                        continue;
                    }

                    $copyId = (string) Str::uuid();

                    $row = (array) $book;
                    $row['audiobook_id'] = $copyId;
                    $row['caregiver_id'] = $caregiverId;
                    $row['visibility']   = 'private';
                    DB::table('audiobooks')->insert($row);

                    $pageRows = $pages->map(function ($page) use ($copyId) {
                        $p = (array) $page;
                        $p['page_id']      = (string) Str::uuid();
                        $p['audiobook_id'] = $copyId;
                        return $p;
                    })->all();
                    foreach (array_chunk($pageRows, 200) as $chunk) {
                        DB::table('audiobook_pages')->insert($chunk);
                    }

                    $children = $childrenOf->get($caregiverId, []);
                    if (!empty($children)) {
                        DB::table('listening_history')
                            ->where('audiobook_id', $bookId)
                            ->whereIn('child_id', $children)
                            ->update(['audiobook_id' => $copyId]);
                    }

                    DB::table('hub_posts')
                        ->where('audiobook_id', $bookId)
                        ->where('shared_by', $caregiverId)
                        ->update(['audiobook_id' => $copyId]);
                }

                DB::table('audiobooks')
                    ->where('audiobook_id', $bookId)
                    ->update([
                        'caregiver_id' => $keeper,
                        'visibility'   => 'private',
                    ]);
            });
        }
    }

    // The copies are now separate books that each family may have changed.
    // There's no safe way to merge them back into one shared book.
    public function down(): void
    {
    }
};
