<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/* Friends now get a one-to-one chat the moment they connect. This gives
   friendships made before that a chat too, so every friend shows up in the
   Chat tab. Friends who already have a direct chat are left as they are. */
return new class extends Migration
{
    public function up(): void
    {
        $friendships = DB::table('friendships')
            ->where('status', 'accepted')
            ->get(['requester_id', 'addressee_id', 'updated_at']);

        foreach ($friendships as $f) {
            $shared = DB::table('conversation_participants as a')
                ->join('conversation_participants as b', 'a.conversation_id', '=', 'b.conversation_id')
                ->join('conversations as c', 'c.conversation_id', '=', 'a.conversation_id')
                ->where('a.caregiver_id', $f->requester_id)
                ->where('b.caregiver_id', $f->addressee_id)
                ->where('c.type', 'direct')
                ->exists();
            if ($shared) {
                continue;
            }

            DB::transaction(function () use ($f) {
                $now = now();
                // Dated when they became friends, so it sorts sensibly in the list.
                $at = $f->updated_at ?? $now;
                $id = (string) Str::uuid();
                DB::table('conversations')->insert([
                    'conversation_id' => $id,
                    'type'            => 'direct',
                    'title'           => null,
                    'created_by'      => $f->requester_id,
                    'created_at'      => $at,
                    'updated_at'      => $at,
                ]);
                DB::table('conversation_participants')->insert([
                    [
                        'id'              => (string) Str::uuid(),
                        'conversation_id' => $id,
                        'caregiver_id'    => $f->requester_id,
                        'role'            => 'admin',
                        'last_read_at'    => null,
                        'created_at'      => $at,
                        'updated_at'      => $at,
                    ],
                    [
                        'id'              => (string) Str::uuid(),
                        'conversation_id' => $id,
                        'caregiver_id'    => $f->addressee_id,
                        'role'            => 'member',
                        'last_read_at'    => null,
                        'created_at'      => $at,
                        'updated_at'      => $at,
                    ],
                ]);
            });
        }
    }

    // The chats may hold messages by now, so they are kept.
    public function down(): void
    {
    }
};
