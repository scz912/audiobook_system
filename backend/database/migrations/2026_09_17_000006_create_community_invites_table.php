<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* Invites that let a family join the private hub. A caregiver shares the
   `code`; whoever redeems it becomes a community member. Keeps the hub
   closed instead of public. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('community_invites', function (Blueprint $table) {
            $table->uuid('invite_id')->primary();
            $table->foreignUuid('inviter_id')
                ->constrained('caregivers', 'caregiver_id')
                ->cascadeOnDelete();
            $table->string('code', 12)->unique();
            $table->string('email')->nullable();
            $table->enum('status', ['pending', 'accepted', 'revoked'])->default('pending');
            $table->foreignUuid('accepted_by')
                ->nullable()
                ->constrained('caregivers', 'caregiver_id')
                ->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('community_invites');
    }
};
