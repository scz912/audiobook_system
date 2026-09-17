<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* Comments on a hub post. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('hub_comments', function (Blueprint $table) {
            $table->uuid('comment_id')->primary();
            $table->foreignUuid('post_id')
                ->constrained('hub_posts', 'post_id')
                ->cascadeOnDelete();
            $table->foreignUuid('caregiver_id')
                ->constrained('caregivers', 'caregiver_id')
                ->cascadeOnDelete();
            $table->text('body');
            $table->timestamps();

            $table->index(['post_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('hub_comments');
    }
};
