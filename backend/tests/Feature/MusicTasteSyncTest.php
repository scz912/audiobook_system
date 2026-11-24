<?php

namespace Tests\Feature;

use App\Models\Caregiver;
use App\Models\MusicTasteCount;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class MusicTasteSyncTest extends TestCase
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

    private function counts(string $childId): array
    {
        return MusicTasteCount::where('child_id', $childId)->orderBy('day')->orderBy('genre')
            ->get()->map(fn ($c) => [$c->day->format('Y-m-d'), $c->genre, $c->plays])->all();
    }

    public function test_sending_the_same_days_again_replaces_them_and_keeps_older_ones(): void
    {
        $me = $this->caregiver();
        $child = $me->childProfiles()->create(['name' => 'Mia', 'age' => 8]);
        $url = "/api/insights/{$child->child_id}/music-taste";

        $this->withToken($me->session_token)->postJson($url, [
            'from'   => '2026-11-01',
            'counts' => [
                ['day' => '2026-11-01', 'genre' => 'K-Pop', 'plays' => 2],
                ['day' => '2026-11-02', 'genre' => 'Pop',   'plays' => 1],
            ],
        ])->assertOk();

        // Later the phone has forgotten 11-01 and heard more on 11-02.
        $this->withToken($me->session_token)->postJson($url, [
            'from'   => '2026-11-02',
            'counts' => [
                ['day' => '2026-11-02', 'genre' => 'Pop',  'plays' => 3],
                ['day' => '2026-11-03', 'genre' => 'Jazz', 'plays' => 1],
            ],
        ])->assertOk()->assertJsonPath('data.rows', 2);

        $this->assertSame([
            ['2026-11-01', 'K-Pop', 2],
            ['2026-11-02', 'Pop', 3],
            ['2026-11-03', 'Jazz', 1],
        ], $this->counts($child->child_id));
    }

    public function test_another_familys_child_is_not_found(): void
    {
        $other = $this->caregiver();
        $child = $other->childProfiles()->create(['name' => 'Sam', 'age' => 7]);
        $me = $this->caregiver();

        $this->withToken($me->session_token)->postJson("/api/insights/{$child->child_id}/music-taste", [
            'from' => '2026-11-01', 'counts' => [],
        ])->assertNotFound();
    }

    public function test_a_day_before_from_is_refused(): void
    {
        $me = $this->caregiver();
        $child = $me->childProfiles()->create(['name' => 'Mia', 'age' => 8]);

        $this->withToken($me->session_token)->postJson("/api/insights/{$child->child_id}/music-taste", [
            'from'   => '2026-11-05',
            'counts' => [['day' => '2026-11-01', 'genre' => 'Pop', 'plays' => 1]],
        ])->assertStatus(422);
        $this->assertSame([], $this->counts($child->child_id));
    }
}
