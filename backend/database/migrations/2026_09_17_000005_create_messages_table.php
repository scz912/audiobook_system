<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* One chat message in a conversation. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('messages', function (Blueprint $table) {
            $table->uuid('message_id')->primary();
            $table->foreignUuid('conversation_id')
                ->constrained('conversations', 'conversation_id')
                ->cascadeOnDelete();
            $table->foreignUuid('sender_id')
                ->constrained('caregivers', 'caregiver_id')
                ->cascadeOnDelete();
            $table->text('body');
            $table->timestamps();

            // Loading a thread reads by conversation, newest last.
            $table->index(['conversation_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('messages');
    }
};
