<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('audiobooks', function (Blueprint $table) {
            $table->string('video_file', 500)->nullable()->after('audio_file');
        });

        // Add 'Video' to the type enum.
        DB::statement("ALTER TABLE audiobooks MODIFY COLUMN type ENUM('Audio','Text','Video') NOT NULL DEFAULT 'Text'");
    }

    public function down(): void
    {
        DB::statement("ALTER TABLE audiobooks MODIFY COLUMN type ENUM('Audio','Text') NOT NULL DEFAULT 'Text'");

        Schema::table('audiobooks', function (Blueprint $table) {
            $table->dropColumn('video_file');
        });
    }
};
