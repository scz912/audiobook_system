<?php

namespace Tests\Feature;

use App\Models\Audiobook;
use App\Models\Caregiver;
use App\Models\HubPost;
use App\Services\GeminiService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

class AudiobookVisibilityTest extends TestCase
{
    use RefreshDatabase;

    /* Older migrations use MySQL-only ALTER statements, so this can't run on
       the default SQLite setup. To run it, point DB_CONNECTION and DB_DATABASE
       at a throwaway MySQL database: RefreshDatabase wipes whatever it's given. */
    protected function setUp(): void
    {
        if (($_ENV['DB_CONNECTION'] ?? getenv('DB_CONNECTION')) === 'sqlite') {
            $this->markTestSkipped('Needs a throwaway MySQL database.');
        }
        parent::setUp();
    }

    private function caregiver(bool $member = false): Caregiver
    {
        return Caregiver::create([
            'name'                => 'Caregiver',
            'email'               => Str::uuid() . '@example.test',
            'pin'                 => '1234',
            'session_token'       => Str::random(40),
            'session_expires'     => now('Asia/Kuala_Lumpur')->addDay(),
            'is_community_member' => $member,
        ]);
    }

    private function book(?Caregiver $owner, string $visibility): Audiobook
    {
        return Audiobook::create([
            'caregiver_id' => $owner?->caregiver_id,
            'title'        => "A {$visibility} story",
            'visibility'   => $visibility,
        ]);
    }

    private function api(Caregiver $caregiver, string $path, array $body = []): TestResponse
    {
        return $this->withToken($caregiver->session_token)->postJson("/api{$path}", $body);
    }

    private function listedIds(Caregiver $caregiver): array
    {
        return array_column($this->api($caregiver, '/content/list')->json('data.items'), 'audiobook_id');
    }

    public function test_private_book_is_listed_and_counted_only_for_its_owner(): void
    {
        $owner = $this->caregiver();
        $other = $this->caregiver();
        $private = $this->book($owner, 'private');
        $public = $this->book($owner, 'public');

        $this->assertEqualsCanonicalizing(
            [$private->audiobook_id, $public->audiobook_id],
            $this->listedIds($owner)
        );
        $this->assertSame([$public->audiobook_id], $this->listedIds($other));

        $this->api($owner, '/content/summary')->assertJsonPath('data.total_items', 2);
        $this->api($other, '/content/summary')->assertJsonPath('data.total_items', 1);
    }

    public function test_private_book_can_only_be_opened_by_its_owner(): void
    {
        $owner = $this->caregiver();
        $book = $this->book($owner, 'private');

        $this->api($owner, "/audiobooks/{$book->audiobook_id}")
            ->assertOk()
            ->assertJsonPath('data.is_mine', true);
        $this->api($this->caregiver(), "/audiobooks/{$book->audiobook_id}")->assertNotFound();
    }

    public function test_other_caregivers_cannot_change_a_book_even_if_it_is_public(): void
    {
        $owner = $this->caregiver();
        $other = $this->caregiver();

        foreach (['public', 'private'] as $visibility) {
            $book = $this->book($owner, $visibility);
            $id = $book->audiobook_id;

            $this->api($other, "/content/{$id}/update", ['title' => 'Taken'])->assertNotFound();
            $this->api($other, "/content/{$id}/update", ['visibility' => 'public'])->assertNotFound();
            $this->api($other, "/content/{$id}/pages", ['text' => 'Extra'])->assertNotFound();
            $this->api($other, "/content/{$id}/delete")->assertNotFound();

            $fresh = $book->fresh();
            $this->assertSame("A {$visibility} story", $fresh->title);
            $this->assertSame($visibility, $fresh->visibility);
            $this->assertSame(0, $fresh->pages()->count());
        }
    }

    public function test_public_book_shows_as_read_only_to_other_caregivers(): void
    {
        $owner = $this->caregiver();
        $this->book($owner, 'public');

        $this->api($owner, '/content/list')->assertJsonPath('data.items.0.can_edit', true);
        $this->api($this->caregiver(), '/content/list')
            ->assertJsonPath('data.items.0.can_edit', false)
            ->assertJsonPath('data.items.0.is_mine', false);
    }

    public function test_owner_can_switch_visibility_later(): void
    {
        $owner = $this->caregiver();
        $other = $this->caregiver();
        $book = $this->book($owner, 'private');

        $this->api($owner, "/content/{$book->audiobook_id}/update", ['visibility' => 'public'])
            ->assertOk()
            ->assertJsonPath('data.visibility', 'public');

        $this->assertSame([$book->audiobook_id], $this->listedIds($other));
    }

    public function test_books_from_before_owners_stay_public_and_editable(): void
    {
        $book = $this->book(null, 'public');
        $caregiver = $this->caregiver();
        $id = $book->audiobook_id;

        $this->assertSame([$id], $this->listedIds($caregiver));
        $this->api($caregiver, "/content/{$id}/update", ['title' => 'Renamed'])->assertOk();

        // Nobody owns it, so going private would hide it from everyone.
        $this->api($caregiver, "/content/{$id}/update", ['visibility' => 'private'])->assertStatus(422);
        $this->assertSame('public', $book->fresh()->visibility);
    }

    public function test_upload_needs_a_visibility_choice_and_saves_the_owner(): void
    {
        $caregiver = $this->caregiver();

        $this->api($caregiver, '/content/create', ['title' => 'Mine'])->assertStatus(422);

        $id = $this->api($caregiver, '/content/create', ['title' => 'Mine', 'visibility' => 'private'])
            ->assertOk()
            ->assertJsonPath('data.visibility', 'private')
            ->json('data.audiobook_id');

        $this->assertSame($caregiver->caregiver_id, Audiobook::find($id)->caregiver_id);
    }

    public function test_generating_needs_a_visibility_choice_and_saves_the_owner(): void
    {
        $this->mock(GeminiService::class, function ($mock) {
            $mock->allows('isConfigured')->andReturnTrue();
            $mock->allows('generateStory')->andReturn([
                'content' => 'A story.',
                'pages'   => [['text' => 'A story.', 'image_prompt' => 'A turtle']],
            ]);
        });
        $caregiver = $this->caregiver();

        $this->api($caregiver, '/content/generate', ['topic' => 'Turtles'])->assertStatus(422);
        $this->assertSame(0, Audiobook::count());

        $id = $this->api($caregiver, '/content/generate', ['topic' => 'Turtles', 'visibility' => 'private'])
            ->assertOk()
            ->assertJsonPath('data.visibility', 'private')
            ->assertJsonPath('data.is_mine', true)
            ->json('data.audiobook_id');

        $this->assertSame($caregiver->caregiver_id, Audiobook::find($id)->caregiver_id);
        $this->assertSame([], $this->listedIds($this->caregiver()));
    }

    public function test_private_book_cannot_be_shared_to_the_hub(): void
    {
        $owner = $this->caregiver(member: true);
        $other = $this->caregiver(member: true);
        $book = $this->book($owner, 'private');

        $this->api($owner, '/hub/create', ['audiobook_id' => $book->audiobook_id])
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'BOOK_PRIVATE');
        $this->api($other, '/hub/create', ['audiobook_id' => $book->audiobook_id])->assertNotFound();

        $this->assertSame(0, HubPost::count());
    }

    public function test_book_made_private_after_sharing_leaves_other_members_feeds(): void
    {
        $owner = $this->caregiver(member: true);
        $other = $this->caregiver(member: true);
        $book = $this->book($owner, 'public');

        $this->api($owner, '/hub/create', ['audiobook_id' => $book->audiobook_id])->assertOk();
        $this->api($owner, '/hub/create', ['audiobook_id' => $book->audiobook_id, 'caption' => 'Lovely'])->assertOk();

        $book->update(['visibility' => 'private']);

        // The owner keeps both. Others keep only the caption, with no story.
        $this->api($owner, '/hub/feed')->assertJsonCount(2, 'data');
        $this->api($other, '/hub/feed')
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.caption', 'Lovely')
            ->assertJsonPath('data.0.audiobook', null);
    }
}
