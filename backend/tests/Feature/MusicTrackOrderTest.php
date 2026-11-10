<?php

namespace Tests\Feature;

use App\Models\Caregiver;
use App\Models\MusicTrack;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class MusicTrackOrderTest extends TestCase
{
    use RefreshDatabase;

    // Same constraint as AudiobookVisibilityTest: needs a throwaway MySQL database.
    protected function setUp(): void
    {
        if (($_ENV['DB_CONNECTION'] ?? getenv('DB_CONNECTION')) === 'sqlite') {
            $this->markTestSkipped('Needs a throwaway MySQL database.');
        }
        parent::setUp();
    }

    private function caregiver(): Caregiver
    {
        return Caregiver::create([
            'name'            => 'Parent',
            'email'           => Str::uuid() . '@example.test',
            'pin'             => '1234',
            'session_token'   => Str::random(40),
            'session_expires' => now('Asia/Kuala_Lumpur')->addDay(),
        ]);
    }

    private function track(?string $owner, string $title, $at): MusicTrack
    {
        $t = MusicTrack::create([
            'caregiver_id' => $owner,
            'title'        => $title,
            'file_path'    => 'storage/uploads/bgm/x.mp3',
            'status'       => 'active',
        ]);
        $t->created_at = $at;
        $t->save();
        return $t;
    }

    // A piano song saved a moment ago should be the first thing in the list.
    public function test_own_tracks_come_first_newest_on_top(): void
    {
        MusicTrack::query()->delete();
        $me = $this->caregiver();
        $other = $this->caregiver();
        $this->track(null, 'Built-in', now()->subDays(3));
        $this->track($me->caregiver_id, 'Old song', now()->subDay());
        $this->track($me->caregiver_id, 'New song', now());
        $this->track($other->caregiver_id, 'Not mine', now());

        $titles = collect(
            $this->withToken($me->session_token)
                ->postJson('/api/music-tracks/list')
                ->assertOk()
                ->json('data.tracks')
        )->pluck('title')->all();

        $this->assertSame(['New song', 'Old song', 'Built-in'], $titles);
    }
}
