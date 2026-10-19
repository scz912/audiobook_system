<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* Interactive audiobooks. A book is "linear" (read straight through) or
   "interactive" (some pages pause and ask the child to pick a choice).

   How the pages describe the flow:
   - Interaction page: has `choices` (2-4 short answers). `is_split` says
     whether the next page splits into one version per choice.
   - Placeholder response page: the page right after a non-split
     interaction. Its text holds the {choice} token, which the player swaps
     for the child's answer.
   - Split pages: the page right after a split interaction, stored as two
     rows with the SAME page_number and different page_id. `branch_index`
     (0 or 1) says which choice leads to that version. Every other page has
     branch_index null and is shown to everyone. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('audiobooks', function (Blueprint $table) {
            $table->string('book_format', 20)->default('linear')->after('type'); // linear | interactive
        });

        Schema::table('audiobook_pages', function (Blueprint $table) {
            $table->json('choices')->nullable()->after('text');
            $table->boolean('is_split')->default(false)->after('choices');
            $table->unsignedTinyInteger('branch_index')->nullable()->after('is_split');
        });
    }

    public function down(): void
    {
        Schema::table('audiobook_pages', function (Blueprint $table) {
            $table->dropColumn(['choices', 'is_split', 'branch_index']);
        });

        Schema::table('audiobooks', function (Blueprint $table) {
            $table->dropColumn('book_format');
        });
    }
};
