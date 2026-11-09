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

    public function test_library_holds_only_my_books_and_the_older_shared_ones(): void
    {
        $owner = $this->caregiver();
        $other = $this->caregiver();
        $mine = $this->book($owner, 'private');
        $starter = $this->book(null, 'public');
        $this->book($other, 'private');

        $this->assertEqualsCanonicalizing(
            [$mine->audiobook_id, $starter->audiobook_id],
            $this->listedIds($owner)
        );
        $this->api($owner, '/content/summary')->assertJsonPath('data.total_items', 2);
    }

    public function test_upload_is_always_private_to_its_author(): void
    {
        $caregiver = $this->caregiver();

        // A stale "public" from an old app version is ignored.
        $id = $this->api($caregiver, '/content/create', ['title' => 'Mine', 'visibility' => 'public'])
            ->assertOk()
            ->assertJsonPath('data.is_mine', true)
            ->json('data.audiobook_id');

        $book = Audiobook::find($id);
        $this->assertSame($caregiver->caregiver_id, $book->caregiver_id);
        $this->assertSame('private', $book->visibility);
        $this->assertSame([], $this->listedIds($this->caregiver()));
    }

    public function test_generated_book_does_not_reach_other_caregivers(): void
    {
        $this->mock(GeminiService::class, function ($mock) {
            $mock->allows('isConfigured')->andReturnTrue();
            $mock->allows('generateStory')->andReturn([
                'content' => 'A story.',
                'pages'   => [['text' => 'A story.', 'image_prompt' => 'A turtle']],
            ]);
        });
        $caregiver = $this->caregiver();

        $id = $this->api($caregiver, '/content/generate', ['topic' => 'Turtles'])
            ->assertOk()
            ->json('data.audiobook_id');

        $this->assertSame('private', Audiobook::find($id)->visibility);
        $this->assertSame([$id], $this->listedIds($caregiver));
        $this->assertSame([], $this->listedIds($this->caregiver()));
        $this->api($this->caregiver(), "/audiobooks/{$id}")->assertNotFound();
    }

    public function test_other_caregivers_cannot_change_my_book(): void
    {
        $owner = $this->caregiver();
        $other = $this->caregiver(member: true);
        $book = $this->book($owner, 'private');
        $id = $book->audiobook_id;

        // Even once it's shared in the hub.
        HubPost::create(['audiobook_id' => $id, 'shared_by' => $owner->caregiver_id]);

        $this->api($other, "/content/{$id}/update", ['title' => 'Taken'])->assertNotFound();
        $this->api($other, "/content/{$id}/pages", ['text' => 'Extra'])->assertNotFound();
        $this->api($other, "/content/{$id}/delete")->assertNotFound();

        $fresh = $book->fresh();
        $this->assertSame('A private story', $fresh->title);
        $this->assertSame(0, $fresh->pages()->count());
    }

    // Each caregiver now gets their own copy of the older books (see the
    // give_each_caregiver_own_copy_of_shared_books migration), so a book
    // with no owner can't be changed: one family's edit would hit everyone.
    public function test_books_with_no_owner_cannot_be_edited(): void
    {
        $book = $this->book(null, 'public');

        $this->api($this->caregiver(), "/content/{$book->audiobook_id}/update", ['title' => 'Renamed'])
            ->assertNotFound();
        $this->assertSame('A public story', $book->fresh()->title);
    }

    public function test_migration_makes_books_made_with_the_old_public_option_private(): void
    {
        $owned = $this->book($this->caregiver(), 'public');
        $starter = $this->book(null, 'public');

        (require database_path('migrations/2026_11_05_000001_make_owned_audiobooks_private.php'))->up();

        $this->assertSame('private', $owned->fresh()->visibility);
        $this->assertSame('public', $starter->fresh()->visibility);
    }

    public function test_difficulty_reaches_the_story_writer(): void
    {
        // Gemini turns difficulty into sentences per page (see sentencesPerPage).
        $this->mock(GeminiService::class, function ($mock) {
            $mock->allows('isConfigured')->andReturnTrue();
            $mock->expects('generateStory')
                ->withArgs(fn (...$args) => ($args[5] ?? null) === 'Medium')
                ->andReturn([
                    'content' => 'A story.',
                    'pages'   => [['text' => 'A story.', 'image_prompt' => 'A turtle']],
                ]);
        });

        $this->api($this->caregiver(), '/content/generate', [
            'topic'      => 'Turtles',
            'difficulty' => 'Medium',
        ])->assertOk()->assertJsonPath('data.difficulty', 'medium');
    }

    public function test_my_private_book_can_be_shared_and_opened_by_members(): void
    {
        $owner = $this->caregiver(member: true);
        $member = $this->caregiver(member: true);
        $outsider = $this->caregiver();
        $book = $this->book($owner, 'private');
        $id = $book->audiobook_id;

        // Before sharing, only the author can open it.
        $this->api($member, "/audiobooks/{$id}")->assertNotFound();

        $this->api($owner, '/hub/create', ['audiobook_id' => $id])->assertOk();

        $this->api($member, '/hub/feed')->assertJsonPath('data.0.audiobook.audiobook_id', $id);
        $this->api($member, "/audiobooks/{$id}")
            ->assertOk()
            ->assertJsonPath('data.is_mine', false);
        // It still isn't in their library, and non-members can't open it.
        $this->assertSame([], $this->listedIds($member));
        $this->api($outsider, "/audiobooks/{$id}")->assertNotFound();
    }

    public function test_someone_elses_book_cannot_be_shared(): void
    {
        $owner = $this->caregiver(member: true);
        $other = $this->caregiver(member: true);
        $book = $this->book($owner, 'private');

        $this->api($other, '/hub/create', ['audiobook_id' => $book->audiobook_id])->assertNotFound();
        $this->assertSame(0, HubPost::count());
    }

    public function test_deleting_the_post_takes_the_book_back_out_of_the_hub(): void
    {
        $owner = $this->caregiver(member: true);
        $member = $this->caregiver(member: true);
        $book = $this->book($owner, 'private');

        $postId = $this->api($owner, '/hub/create', ['audiobook_id' => $book->audiobook_id])
            ->json('data.post_id');
        $this->api($owner, "/hub/{$postId}/delete")->assertOk();

        $this->api($member, "/audiobooks/{$book->audiobook_id}")->assertNotFound();
    }
}
