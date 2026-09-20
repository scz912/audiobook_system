<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* Let a hub post be text-only. `audiobook_id` becomes nullable so a caregiver
   can share just a caption, just an audiobook, or both. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('hub_posts', function (Blueprint $table) {
            $table->dropForeign(['audiobook_id']);
            $table->uuid('audiobook_id')->nullable()->change();
            $table->foreign('audiobook_id')
                ->references('audiobook_id')->on('audiobooks')
                ->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('hub_posts', function (Blueprint $table) {
            $table->dropForeign(['audiobook_id']);
            $table->uuid('audiobook_id')->nullable(false)->change();
            $table->foreign('audiobook_id')
                ->references('audiobook_id')->on('audiobooks')
                ->cascadeOnDelete();
        });
    }
};
