<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* Friend links between caregivers. One row per pair. `status` covers the
   request flow (pending → accepted) and blocking. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('friendships', function (Blueprint $table) {
            $table->uuid('friendship_id')->primary();
            $table->foreignUuid('requester_id')
                ->constrained('caregivers', 'caregiver_id')
                ->cascadeOnDelete();
            $table->foreignUuid('addressee_id')
                ->constrained('caregivers', 'caregiver_id')
                ->cascadeOnDelete();
            $table->enum('status', ['pending', 'accepted', 'blocked'])->default('pending');
            $table->timestamps();

            // Only one link per pair, and quick lookups from either side.
            $table->unique(['requester_id', 'addressee_id']);
            $table->index('addressee_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('friendships');
    }
};
