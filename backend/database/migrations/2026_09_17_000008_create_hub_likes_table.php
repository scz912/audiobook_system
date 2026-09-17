<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* Likes on a hub post. One row per person per post. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('hub_likes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('post_id')
                ->constrained('hub_posts', 'post_id')
                ->cascadeOnDelete();
            $table->foreignUuid('caregiver_id')
                ->constrained('caregivers', 'caregiver_id')
                ->cascadeOnDelete();
            $table->timestamps();

            $table->unique(['post_id', 'caregiver_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('hub_likes');
    }
};
