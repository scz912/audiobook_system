<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/* Let the person who sent a friend request find out the answer. A declined
   request is kept as 'declined' (it used to be deleted) until the sender has
   seen it, and `requester_seen` is false while an accept or decline is
   still unread by the sender. That drives the red dot on the Community tab. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('friendships', function (Blueprint $table) {
            $table->enum('status', ['pending', 'accepted', 'declined', 'blocked'])
                ->default('pending')
                ->change();
            $table->boolean('requester_seen')->default(true)->after('status');
        });
    }

    public function down(): void
    {
        DB::table('friendships')->where('status', 'declined')->delete();
        Schema::table('friendships', function (Blueprint $table) {
            $table->dropColumn('requester_seen');
            $table->enum('status', ['pending', 'accepted', 'blocked'])
                ->default('pending')
                ->change();
        });
    }
};
