<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* One caregiver's settings for another member: favorite, blocked, muted,
   and the background of their chat. Each person keeps their own row, so
   my settings for you don't change what you see. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('contact_settings', function (Blueprint $table) {
            $table->uuid('id')->primary();
            // Whose settings these are.
            $table->foreignUuid('caregiver_id')
                ->constrained('caregivers', 'caregiver_id')
                ->cascadeOnDelete();
            // The person they're about.
            $table->foreignUuid('contact_id')
                ->constrained('caregivers', 'caregiver_id')
                ->cascadeOnDelete();
            $table->boolean('is_favorite')->default(false);
            $table->boolean('is_blocked')->default(false);
            $table->boolean('is_muted')->default(false);
            // none | color (#RRGGBB) | gradient (a name the app knows) | image (stored path)
            $table->string('background_type', 10)->default('none');
            $table->string('background_value', 255)->nullable();
            $table->timestamps();

            $table->unique(['caregiver_id', 'contact_id']);
            // "Has anyone blocked me?" looks up by contact.
            $table->index(['contact_id', 'is_blocked']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('contact_settings');
    }
};
