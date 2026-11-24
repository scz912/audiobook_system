<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* What a child listens to in YouTube and YouTube Music, as genre counts
   per day (see MusicTasteService in the app). Only the genre and how many
   plays: never song names. The phone sends its last days again on every
   sync, so a (child, day, genre) row is replaced, not added to. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('music_taste_counts', function (Blueprint $table) {
            $table->id();
            $table->foreignUuid('child_id')
                ->constrained('child_profiles', 'child_id')
                ->cascadeOnDelete();
            $table->date('day');
            $table->string('genre', 60);
            $table->unsignedInteger('plays');
            $table->timestamps();

            $table->unique(['child_id', 'day', 'genre']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('music_taste_counts');
    }
};
