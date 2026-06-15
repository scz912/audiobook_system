<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* Keep each page's image prompt so a job can redraw the picture later. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('audiobook_pages', function (Blueprint $table) {
            $table->text('image_prompt')->nullable()->after('text');
        });
    }

    public function down(): void
    {
        Schema::table('audiobook_pages', function (Blueprint $table) {
            $table->dropColumn('image_prompt');
        });
    }
};
