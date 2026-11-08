<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* Lets a chat message carry an audiobook, and lets a caregiver keep their
   own copy of a book someone shared with them.

   - messages.audiobook_id: the book attached to the message, if any. If
     the owner later deletes the book the message stays, just without it.
   - audiobooks.source_audiobook_id: the book this one was copied from, so
     saving the same shared book twice returns the copy already made. Not
     a foreign key - the original may be deleted while the copy lives on. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('messages', function (Blueprint $table) {
            $table->foreignUuid('audiobook_id')
                ->nullable()
                ->after('body')
                ->constrained('audiobooks', 'audiobook_id')
                ->nullOnDelete();
        });

        Schema::table('audiobooks', function (Blueprint $table) {
            $table->uuid('source_audiobook_id')->nullable()->after('caregiver_id');
            $table->index(['caregiver_id', 'source_audiobook_id']);
        });
    }

    public function down(): void
    {
        Schema::table('audiobooks', function (Blueprint $table) {
            $table->dropIndex(['caregiver_id', 'source_audiobook_id']);
            $table->dropColumn('source_audiobook_id');
        });

        Schema::table('messages', function (Blueprint $table) {
            $table->dropConstrainedForeignId('audiobook_id');
        });
    }
};
