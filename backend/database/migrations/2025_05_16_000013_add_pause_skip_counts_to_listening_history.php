<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /* Count how often the child paused or skipped in a session. Gemini
       uses these to work out pause and skip rates. */
    public function up(): void
    {
        Schema::table('listening_history', function (Blueprint $table) {
            $table->unsignedInteger('pause_count')->default(0)->after('completed');
            $table->unsignedInteger('skip_count')->default(0)->after('pause_count');
        });
    }

    public function down(): void
    {
        Schema::table('listening_history', function (Blueprint $table) {
            $table->dropColumn(['pause_count', 'skip_count']);
        });
    }
};
