<?php

namespace Tests\Feature;

use App\Models\Caregiver;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

// Favorite, block, mute and chat background for a contact.
class ContactSettingsTest extends TestCase
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

    private function member(string $name = 'Family'): Caregiver
    {
        return Caregiver::create([
            'name'                => $name,
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

    private function befriend(Caregiver $a, Caregiver $b): void
    {
        $this->api($a, '/friends/request', ['caregiver_id' => $b->caregiver_id])->assertOk();
        $id = $this->api($b, '/friends/pending')->json('data.0.friendship_id');
        $this->api($b, '/friends/respond', ['friendship_id' => $id, 'action' => 'accept'])->assertOk();
    }

    public function test_settings_start_at_defaults_and_save_per_person(): void
    {
        $me = $this->member();
        $soh = $this->member('Soh');

        $this->api($me, "/contacts/{$soh->caregiver_id}")
            ->assertOk()
            ->assertJsonPath('data.is_favorite', false)
            ->assertJsonPath('data.is_muted', false)
            ->assertJsonPath('data.background.type', 'none');

        $this->api($me, "/contacts/{$soh->caregiver_id}/update", ['is_favorite' => true, 'is_muted' => true])
            ->assertJsonPath('data.is_favorite', true)
            ->assertJsonPath('data.is_muted', true)
            ->assertJsonPath('data.is_blocked', false);

        // My settings don't change Soh's view of me.
        $this->api($soh, "/contacts/{$me->caregiver_id}")->assertJsonPath('data.is_favorite', false);

        $this->api($me, '/contacts/favorites')
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.name', 'Soh');
        $this->api($me, "/contacts/{$me->caregiver_id}")->assertStatus(422);
    }

    public function test_favorites_are_pinned_on_top_of_the_chat_list(): void
    {
        $me = $this->member();
        $soh = $this->member('Soh');
        $sss = $this->member('sss');
        $this->befriend($me, $soh);
        $this->befriend($me, $sss);
        // sss is the newest chat; make Soh the favorite.
        $this->api($me, "/contacts/{$soh->caregiver_id}/update", ['is_favorite' => true]);

        $this->api($me, '/chat')
            ->assertJsonPath('data.0.title', 'Soh')
            ->assertJsonPath('data.0.contact.is_favorite', true)
            ->assertJsonPath('data.1.contact.is_favorite', false);
    }

    public function test_blocking_stops_messages_both_ways_until_unblocked(): void
    {
        $me = $this->member();
        $soh = $this->member('Soh');
        $this->befriend($me, $soh);
        $chat = $this->api($me, '/chat')->json('data.0.conversation_id');

        $this->api($me, "/contacts/{$soh->caregiver_id}/update", ['is_blocked' => true])->assertOk();
        $this->api($me, "/chat/{$chat}/send", ['body' => 'hi'])->assertForbidden();
        $this->api($soh, "/chat/{$chat}/send", ['body' => 'hi'])->assertForbidden();
        $this->api($me, '/contacts/blocked')->assertJsonPath('data.0.name', 'Soh');
        $this->api($me, '/chat')->assertJsonPath('data.0.contact.is_blocked', true);

        $this->api($me, "/contacts/{$soh->caregiver_id}/update", ['is_blocked' => false]);
        $this->api($soh, "/chat/{$chat}/send", ['body' => 'hi again'])->assertOk();
        $this->api($me, '/contacts/blocked')->assertJsonCount(0, 'data');
    }

    public function test_blocked_people_are_hidden_from_search_requests_and_the_feed(): void
    {
        $me = $this->member();
        $soh = $this->member('Soh');
        $this->api($soh, '/hub/create', ['caption' => 'Hello'])->assertOk();
        $this->api($me, '/hub/feed')->assertJsonCount(1, 'data');

        $this->api($me, "/contacts/{$soh->caregiver_id}/update", ['is_blocked' => true]);

        $this->api($me, '/hub/feed')->assertJsonCount(0, 'data');
        $this->api($me, '/friends/search', ['search' => 'Soh'])->assertJsonCount(0, 'data');
        $this->api($soh, '/friends/search', ['search' => 'Family'])->assertJsonCount(0, 'data');
        $this->api($soh, '/friends/request', ['caregiver_id' => $me->caregiver_id])->assertForbidden();
    }

    public function test_background_can_be_a_colour_gradient_picture_or_default(): void
    {
        Storage::fake('public');
        $me = $this->member();
        $soh = $this->member('Soh');
        $path = "/contacts/{$soh->caregiver_id}";

        $this->api($me, "{$path}/update", ['background_type' => 'color', 'background_value' => '#C9B6EC'])
            ->assertJsonPath('data.background', ['type' => 'color', 'value' => '#C9B6EC']);
        $this->api($me, "{$path}/update", ['background_type' => 'color', 'background_value' => 'purple'])
            ->assertStatus(422);
        $this->api($me, "{$path}/update", ['background_type' => 'gradient', 'background_value' => 'ocean'])
            ->assertJsonPath('data.background.value', 'ocean');

        // A real 1x1 PNG, so this runs without the GD extension.
        $png = base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
        $url = $this->withToken($me->session_token)
            ->post("/api{$path}/background", ['image' => UploadedFile::fake()->createWithContent('bg.png', $png)], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonPath('data.background.type', 'image')
            ->json('data.background.value');
        $this->assertStringContainsString('/storage/uploads/chat_backgrounds/', $url);
        Storage::disk('public')->assertExists(Str::after($url, '/storage/'));

        $this->api($me, "{$path}/update", ['background_type' => 'none'])
            ->assertJsonPath('data.background', ['type' => 'none', 'value' => null]);
    }
}
