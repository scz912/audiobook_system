<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* Who is in each conversation. `last_read_at` powers the unread badge. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('conversation_participants', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('conversation_id')
                ->constrained('conversations', 'conversation_id')
                ->cascadeOnDelete();
            $table->foreignUuid('caregiver_id')
                ->constrained('caregivers', 'caregiver_id')
                ->cascadeOnDelete();
            $table->enum('role', ['member', 'admin'])->default('member');
            $table->timestamp('last_read_at')->nullable();
            $table->timestamps();

            // One membership row per person per conversation.
            $table->unique(['conversation_id', 'caregiver_id']);
            $table->index('caregiver_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('conversation_participants');
    }
};
