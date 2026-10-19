<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('music_tracks', function (Blueprint $table) {
            // Null = built-in track everyone sees. Set = uploaded by this caregiver (private to them).
            $table->uuid('caregiver_id')->nullable()->after('track_id');
            $table->string('ai_summary', 500)->nullable()->after('duration_secs');   // AI's short description of the music
            $table->string('sensory_notes', 500)->nullable()->after('ai_summary');  // AI's sensory caution, if any
            $table->foreign('caregiver_id')->references('caregiver_id')->on('caregivers')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('music_tracks', function (Blueprint $table) {
            $table->dropForeign(['caregiver_id']);
            $table->dropColumn(['caregiver_id', 'ai_summary', 'sensory_notes']);
        });
    }
};
