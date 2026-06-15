<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /* Where this page starts in the whole-book recording, in milliseconds.
       Page 1 is 0. When the other pages have this set, the player uses
       these exact marks to flip pages and line up the read-along words,
       instead of guessing from word counts. */
    public function up(): void
    {
        Schema::table('audiobook_pages', function (Blueprint $table) {
            $table->unsignedInteger('audio_start_ms')->nullable()->after('image_prompt');
        });
    }

    public function down(): void
    {
        Schema::table('audiobook_pages', function (Blueprint $table) {
            $table->dropColumn('audio_start_ms');
        });
    }
};
