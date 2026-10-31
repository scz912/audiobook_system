<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* Who owns a book and who can see it. A private book is only visible to its
   owner; a public one is visible to everyone.

   Books made before this have no owner, so they stay public and everyone can
   keep using them. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('audiobooks', function (Blueprint $table) {
            $table->uuid('caregiver_id')->nullable()->after('audiobook_id');
            $table->string('visibility', 20)->default('public')->after('status'); // private | public
            // Null rather than cascade: other families may be using a public book.
            $table->foreign('caregiver_id')->references('caregiver_id')->on('caregivers')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('audiobooks', function (Blueprint $table) {
            $table->dropForeign(['caregiver_id']);
            $table->dropColumn(['caregiver_id', 'visibility']);
        });
    }
};
