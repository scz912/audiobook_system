<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* A shared audiobook in the hub. `include_music` is off by default so shared
   copies don't carry copyrighted background music — only the AI story, images,
   and voice are shared unless the track is royalty-free. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('hub_posts', function (Blueprint $table) {
            $table->uuid('post_id')->primary();
            $table->foreignUuid('audiobook_id')
                ->constrained('audiobooks', 'audiobook_id')
                ->cascadeOnDelete();
            $table->foreignUuid('shared_by')
                ->constrained('caregivers', 'caregiver_id')
                ->cascadeOnDelete();
            $table->string('caption', 300)->nullable();
            $table->boolean('include_music')->default(false);
            $table->timestamps();

            // The feed reads newest first.
            $table->index('created_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('hub_posts');
    }
};
