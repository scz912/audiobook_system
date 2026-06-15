<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    // Add 'gentle_female' as a second female narrator voice.
    public function up(): void
    {
        DB::statement(
            "ALTER TABLE caregiver_settings MODIFY narrator_voice "
            . "ENUM('calm_female','gentle_female','warm_male','friendly_child','soothing_elder') "
            . "NOT NULL DEFAULT 'calm_female'"
        );
    }

    public function down(): void
    {
        // Move rows off the new voice before removing it.
        DB::table('caregiver_settings')
            ->where('narrator_voice', 'gentle_female')
            ->update(['narrator_voice' => 'calm_female']);

        DB::statement(
            "ALTER TABLE caregiver_settings MODIFY narrator_voice "
            . "ENUM('calm_female','warm_male','friendly_child','soothing_elder') "
            . "NOT NULL DEFAULT 'calm_female'"
        );
    }
};
