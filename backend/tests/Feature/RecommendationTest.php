<?php

namespace Tests\Feature;

use App\Models\Audiobook;
use App\Models\Caregiver;
use App\Models\ListeningHistory;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class RecommendationTest extends TestCase
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

    private function book(Caregiver $owner, string $title, string $topic, array $extra = []): Audiobook
    {
        return Audiobook::create($extra + [
            'caregiver_id' => $owner->caregiver_id,
            'title'        => $title,
            'topic'        => $topic,
            'type'         => 'Text',
            'difficulty'   => 'easy',
            'language'     => 'en',
            'status'       => 'available',
            'visibility'   => 'private',
        ]);
    }

    public function test_recommends_from_the_familys_own_library_with_a_reason(): void
    {
        Audiobook::query()->delete();
        $me = $this->caregiver();
        $child = $me->childProfiles()->create(['name' => 'Mia', 'age' => 8]);
        $liked = $this->book($me, 'My cat Tom', 'my cat');
        $this->book($me, 'Cat goes to school', 'cat school');
        $this->book($me, 'Rocket ride', 'rocket space');
        // Someone else's private book is never offered.
        $other = $this->caregiver();
        $this->book($other, 'Not yours', 'cat secret');

        ListeningHistory::create([
            'child_id' => $child->child_id, 'audiobook_id' => $liked->audiobook_id,
            'duration_seconds' => 200, 'completed' => true, 'pages_total' => 5, 'pages_reached' => 5,
        ]);

        $data = $this->withToken($me->session_token)
            ->postJson("/api/insights/{$child->child_id}/recommendations", ['mood' => 'calm', 'limit' => 3])
            ->assertOk()
            ->json('data');

        $titles = collect($data['items'])->map(
            fn ($i) => Audiobook::find($i['audiobook_id'])->title
        )->all();
        $this->assertNotContains('Not yours', $titles);
        $this->assertSame('Cat goes to school', $titles[0]);
        $this->assertSame('like_book', $data['items'][0]['reason']['code']);
        $this->assertSame('My cat Tom', $data['items'][0]['reason']['params']['title']);
        $this->assertSame('calm', $data['mood']);
    }

    public function test_only_your_own_children(): void
    {
        $me = $this->caregiver();
        $theirs = $this->caregiver()->childProfiles()->create(['name' => 'Ali', 'age' => 9]);

        $this->withToken($me->session_token)
            ->postJson("/api/insights/{$theirs->child_id}/recommendations")
            ->assertNotFound();
    }
}
