<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('music_tracks', function (Blueprint $table) {
            // One word from a fixed list (Classical, Nature, Pop, Jazz...), set by the AI.
            $table->string('genre', 30)->nullable()->after('tags');
            // Measured from the audio: beats per minute (null when there's no clear beat)...
            $table->unsignedSmallInteger('bpm')->nullable()->after('tempo');
            // ...and how clear the beat is: strong, gentle or none.
            $table->string('beat', 10)->nullable()->after('bpm');
        });
    }

    public function down(): void
    {
        Schema::table('music_tracks', function (Blueprint $table) {
            $table->dropColumn(['genre', 'bpm', 'beat']);
        });
    }
};
