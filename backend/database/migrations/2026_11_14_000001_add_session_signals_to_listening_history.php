<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* What the settings advisor learns from each listening session: how far
   through the book they got, how often they went back a page, and the
   speed, text size and voice they actually listened with (the player's
   icon buttons can change these for one book). All optional, so older
   sessions and older app versions still save. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('listening_history', function (Blueprint $table) {
            $table->unsignedSmallInteger('pages_total')->nullable()->after('skip_count');
            $table->unsignedSmallInteger('pages_reached')->nullable()->after('pages_total');
            $table->unsignedInteger('back_count')->default(0)->after('pages_reached');
            $table->decimal('speed_used', 3, 2)->nullable()->after('back_count');
            $table->decimal('text_scale_used', 3, 2)->nullable()->after('speed_used');
            $table->string('voice_used', 30)->nullable()->after('text_scale_used');
        });
    }

    public function down(): void
    {
        Schema::table('listening_history', function (Blueprint $table) {
            $table->dropColumn([
                'pages_total', 'pages_reached', 'back_count',
                'speed_used', 'text_scale_used', 'voice_used',
            ]);
        });
    }
};
