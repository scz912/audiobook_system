<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/* Every audiobook a caregiver makes is now private to them. Other members
   only reach it when the author shares it in the community hub. Books made
   while the public option existed are switched to private here.

   Older books with no owner stay public: they're the shared starter
   library, and with no owner, going private would hide them from everyone. */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('audiobooks')
            ->whereNotNull('caregiver_id')
            ->where('visibility', 'public')
            ->update(['visibility' => 'private']);
    }

    // Which books were public isn't recorded, so there's nothing to restore.
    public function down(): void
    {
    }
};
