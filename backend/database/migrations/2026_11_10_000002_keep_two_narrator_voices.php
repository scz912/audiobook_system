<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/* Narration now offers two voices: calm_female and warm_male. Settings that
   chose one of the three retired voices move to the nearest one left. */
return new class extends Migration
{
    private const MOVES = [
        'gentle_female'  => 'calm_female',
        'friendly_child' => 'calm_female',
        'soothing_elder' => 'warm_male',
    ];

    public function up(): void
    {
        foreach (['child_settings', 'caregiver_settings'] as $table) {
            foreach (self::MOVES as $from => $to) {
                DB::table($table)->where('narrator_voice', $from)->update(['narrator_voice' => $to]);
            }
        }
    }

    // The old choices aren't recorded, so there's nothing to restore.
    public function down(): void
    {
    }
};
