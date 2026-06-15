<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /* Per-child voice and playback settings — one row per child so the
       caregiver can set each child separately. */
    public function up(): void
    {
        Schema::create('child_settings', function (Blueprint $table) {
            $table->uuid('setting_id')->primary();
            $table->foreignUuid('child_id')
                ->unique()
                ->constrained('child_profiles', 'child_id')
                ->cascadeOnDelete();
            $table->enum('narrator_voice', [
                'calm_female',
                'gentle_female',
                'warm_male',
                'friendly_child',
                'soothing_elder',
            ])->default('calm_female');
            $table->decimal('reading_speed', 3, 2)->default(1.00);
            $table->decimal('volume', 3, 2)->default(0.80);
            $table->decimal('text_scale', 3, 2)->default(1.00);
            $table->boolean('reduced_animations')->default(true);
            $table->boolean('auto_play_next')->default(true);
            $table->boolean('read_along')->default(true);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('child_settings');
    }
};
