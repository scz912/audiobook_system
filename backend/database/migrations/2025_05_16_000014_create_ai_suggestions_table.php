<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /* The latest Gemini tips for each child. One row per child — each
       analyse run overwrites it. The accept/edit/dismiss state for each
       tip lives in the `items` JSON. */
    public function up(): void
    {
        Schema::create('ai_suggestions', function (Blueprint $table) {
            $table->uuid('suggestion_id')->primary();
            $table->foreignUuid('child_id')
                ->unique()
                ->constrained('child_profiles', 'child_id')
                ->cascadeOnDelete();
            // The stats we sent Gemini, kept so the caregiver can see why.
            $table->json('source_stats');
            /* The tips. Each one: { id, setting_key, current_value,
               suggested_value, reason, status }. */
            $table->json('items');
            $table->enum('confidence', ['low', 'normal'])->default('normal');
            // True when we re-served old tips because a fresh run failed.
            $table->boolean('is_stale')->default(false);
            $table->timestamp('generated_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('ai_suggestions');
    }
};
