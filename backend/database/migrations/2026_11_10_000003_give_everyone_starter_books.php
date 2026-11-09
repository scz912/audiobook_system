<?php

use App\Services\StarterLibrary;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/* Give every existing account its own copy of the starter books (three
   linear, three interactive; see App\Services\StarterLibrary). New accounts
   get them at sign-up. Runs once, so a family that deletes a starter book
   doesn't get it back. */
return new class extends Migration
{
    public function up(): void
    {
        $sources = StarterLibrary::sources();
        Log::info('starter books: sources', [
            'books' => $sources->map(fn ($b) => "{$b->book_format}: {$b->title}")->all(),
        ]);
        if ($sources->isEmpty()) {
            return;
        }

        $made = 0;
        foreach (DB::table('caregivers')->pluck('caregiver_id') as $caregiverId) {
            try {
                $made += StarterLibrary::giveTo($caregiverId, $sources);
            } catch (\Throwable $e) {
                // One account failing shouldn't stop everyone else's.
                Log::warning('starter books: copy failed', [
                    'caregiver_id' => $caregiverId,
                    'error'        => $e->getMessage(),
                ]);
            }
        }
        Log::info('starter books: copies made', ['count' => $made]);
    }

    // The copies are each family's own books now; leave them be.
    public function down(): void
    {
    }
};
