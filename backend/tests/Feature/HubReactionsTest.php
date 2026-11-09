<?php

namespace Tests\Feature;

use App\Models\Caregiver;
use App\Models\HubReaction;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

// Emoji reactions on hub posts: one per person, separate from likes.
class HubReactionsTest extends TestCase
{
    use RefreshDatabase;

    private const THUMBS = "\u{1F44D}";
    private const LAUGH = "\u{1F602}";
    private const PARTY = "\u{1F389}";

    // Same constraint as AudiobookVisibilityTest: needs a throwaway MySQL database.
    protected function setUp(): void
    {
        if (($_ENV['DB_CONNECTION'] ?? getenv('DB_CONNECTION')) === 'sqlite') {
            $this->markTestSkipped('Needs a throwaway MySQL database.');
        }
        parent::setUp();
    }

    private function member(): Caregiver
    {
        return Caregiver::create([
            'name'                => 'Family',
            'email'               => Str::uuid() . '@example.test',
            'pin'                 => '1234',
            'session_token'       => Str::random(40),
            'session_expires'     => now('Asia/Kuala_Lumpur')->addDay(),
            'is_community_member' => true,
        ]);
    }

    private function api(Caregiver $caregiver, string $path, array $body = []): TestResponse
    {
        return $this->withToken($caregiver->session_token)->postJson("/api{$path}", $body);
    }

    private function makePost(Caregiver $author): string
    {
        return $this->api($author, '/hub/create', ['caption' => 'Hello'])->json('data.post_id');
    }

    public function test_one_emoji_per_person_and_repeats_do_not_add_up(): void
    {
        $a = $this->member();
        $postId = $this->makePost($a);

        $this->api($a, "/hub/{$postId}/react", ['emoji' => self::THUMBS])
            ->assertOk()
            ->assertJsonPath('data.my_reaction', self::THUMBS)
            ->assertJsonPath('data.reactions', [['emoji' => self::THUMBS, 'count' => 1]]);

        // The same emoji again changes nothing.
        $this->api($a, "/hub/{$postId}/react", ['emoji' => self::THUMBS]);
        $this->api($a, "/hub/{$postId}/react", ['emoji' => self::THUMBS])
            ->assertJsonPath('data.reactions', [['emoji' => self::THUMBS, 'count' => 1]]);

        // Another emoji moves my reaction; still only one from me.
        $this->api($a, "/hub/{$postId}/react", ['emoji' => self::LAUGH])
            ->assertJsonPath('data.my_reaction', self::LAUGH)
            ->assertJsonPath('data.reactions', [['emoji' => self::LAUGH, 'count' => 1]]);
        $this->assertSame(1, HubReaction::count());

        $this->api($a, "/hub/{$postId}/unreact")
            ->assertJsonPath('data.my_reaction', null)
            ->assertJsonPath('data.reactions', []);
    }

    public function test_reactions_and_likes_are_separate(): void
    {
        $a = $this->member();
        $b = $this->member();
        $postId = $this->makePost($a);

        $this->api($a, "/hub/{$postId}/like")->assertJsonPath('data.like_count', 1);
        $this->api($a, "/hub/{$postId}/react", ['emoji' => self::PARTY]);
        $this->api($b, "/hub/{$postId}/react", ['emoji' => self::PARTY]);

        $this->api($b, '/hub/feed')
            ->assertJsonPath('data.0.like_count', 1)
            ->assertJsonPath('data.0.liked_by_me', false)
            ->assertJsonPath('data.0.my_reaction', self::PARTY)
            ->assertJsonPath('data.0.reactions', [['emoji' => self::PARTY, 'count' => 2]]);

        // Taking a reaction off leaves the like alone, and the other way round.
        $this->api($a, "/hub/{$postId}/unreact");
        $this->api($a, '/hub/feed')
            ->assertJsonPath('data.0.liked_by_me', true)
            ->assertJsonPath('data.0.like_count', 1);
        $this->api($a, "/hub/{$postId}/unlike");
        $this->api($b, '/hub/feed')
            ->assertJsonPath('data.0.like_count', 0)
            ->assertJsonPath('data.0.reactions', [['emoji' => self::PARTY, 'count' => 1]]);
    }

    public function test_only_the_offered_emoji_are_accepted(): void
    {
        $a = $this->member();
        $postId = $this->makePost($a);

        $this->api($a, "/hub/{$postId}/react", ['emoji' => 'lol'])->assertStatus(422);
        // The heart is the like button, not a reaction.
        $this->api($a, "/hub/{$postId}/react", ['emoji' => "\u{2764}\u{FE0F}"])->assertStatus(422);
        $this->assertSame(0, HubReaction::count());
    }
}
