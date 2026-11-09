<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* Emoji reactions on hub posts, separate from likes (the heart button).
   Each person leaves at most one emoji on a post: the unique key makes
   picking another emoji replace theirs rather than add a second. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('hub_reactions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('post_id')
                ->constrained('hub_posts', 'post_id')
                ->cascadeOnDelete();
            $table->foreignUuid('caregiver_id')
                ->constrained('caregivers', 'caregiver_id')
                ->cascadeOnDelete();
            $table->string('emoji', 16);
            $table->timestamps();

            $table->unique(['post_id', 'caregiver_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('hub_reactions');
    }
};
