<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* A chat thread — either a one-to-one direct message or a group chat.
   `title` is only used by groups. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('conversations', function (Blueprint $table) {
            $table->uuid('conversation_id')->primary();
            $table->enum('type', ['direct', 'group'])->default('direct');
            $table->string('title', 100)->nullable();
            $table->foreignUuid('created_by')
                ->nullable()
                ->constrained('caregivers', 'caregiver_id')
                ->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('conversations');
    }
};
