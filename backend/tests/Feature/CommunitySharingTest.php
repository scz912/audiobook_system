<?php

namespace Tests\Feature;

use App\Models\Audiobook;
use App\Models\AudiobookPage;
use App\Models\Caregiver;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/* Friends land in the Chat tab, books can be shared in a chat, and a book
   shared in a chat or the hub can be saved into your own library. */
class CommunitySharingTest extends TestCase
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

    private function book(Caregiver $owner, string $title = 'Shared story'): Audiobook
    {
        $book = Audiobook::create([
            'caregiver_id' => $owner->caregiver_id,
            'title'        => $title,
            'visibility'   => 'private',
            'status'       => 'available',
        ]);
        foreach (['One.', 'Two.'] as $i => $text) {
            AudiobookPage::create([
                'audiobook_id' => $book->audiobook_id,
                'page_number'  => $i + 1,
                'text'         => $text,
            ]);
        }
        return $book;
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

    private function directChatId(Caregiver $me): string
    {
        return $this->api($me, '/chat')->json('data.0.conversation_id');
    }

    public function test_accepting_a_friend_puts_them_in_both_chat_lists(): void
    {
        $a = $this->member('Tiew');
        $b = $this->member('Soh');
        $this->befriend($a, $b);

        $this->api($a, '/chat')
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.type', 'direct')
            ->assertJsonPath('data.0.title', 'Soh')
            ->assertJsonPath('data.0.last_message', null);
        $this->api($b, '/chat')->assertJsonPath('data.0.title', 'Tiew');

        // Opening the chat from the profile reuses it instead of making another.
        $this->api($a, '/chat/direct', ['caregiver_id' => $b->caregiver_id])
            ->assertJsonPath('data.conversation_id', $this->directChatId($a));
        $this->api($a, '/chat')->assertJsonCount(1, 'data');
    }

    public function test_existing_friends_without_a_chat_get_one_from_the_migration(): void
    {
        $a = $this->member('Tiew');
        $b = $this->member('sss');
        // A friendship made before friends got a chat automatically.
        \App\Models\Friendship::create([
            'requester_id' => $a->caregiver_id,
            'addressee_id' => $b->caregiver_id,
            'status'       => 'accepted',
        ]);
        $this->api($a, '/chat')->assertJsonCount(0, 'data');

        $migration = require database_path('migrations/2026_11_08_000002_open_chats_for_existing_friends.php');
        $migration->up();
        // Running it again doesn't add a second chat.
        $migration->up();

        $this->api($a, '/chat')
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.title', 'sss');
        $this->api($b, '/chat')->assertJsonPath('data.0.title', 'Tiew');
    }

    public function test_a_book_shared_in_chat_can_be_opened_by_the_friend(): void
    {
        $a = $this->member();
        $b = $this->member();
        $this->befriend($a, $b);
        $book = $this->book($a, 'Dogs and Cats');
        $chat = $this->directChatId($a);

        // Not shared yet: the friend can't open a private book.
        $this->api($b, "/audiobooks/{$book->audiobook_id}")->assertNotFound();

        $this->api($a, "/chat/{$chat}/send", ['audiobook_id' => $book->audiobook_id])
            ->assertOk()
            ->assertJsonPath('data.audiobook.title', 'Dogs and Cats')
            ->assertJsonPath('data.audiobook.in_my_library', true);

        $this->api($b, "/chat/{$chat}/messages")
            ->assertJsonPath('data.0.audiobook.audiobook_id', $book->audiobook_id)
            ->assertJsonPath('data.0.audiobook.in_my_library', false);
        $this->api($b, '/chat')->assertJsonPath('data.0.last_message.body', "\u{1F4D6} Dogs and Cats");
        $this->api($b, "/audiobooks/{$book->audiobook_id}")->assertOk();
    }

    public function test_cannot_share_a_book_you_cannot_open(): void
    {
        $a = $this->member();
        $b = $this->member();
        $stranger = $this->member();
        $this->befriend($a, $b);
        $theirs = $this->book($stranger);

        $this->api($a, '/chat/' . $this->directChatId($a) . '/send', ['audiobook_id' => $theirs->audiobook_id])
            ->assertNotFound();
        // Neither text nor a book: nothing to send.
        $this->api($a, '/chat/' . $this->directChatId($a) . '/send', ['body' => ''])
            ->assertStatus(422);
    }

    public function test_saving_a_shared_book_makes_one_private_copy(): void
    {
        $a = $this->member();
        $b = $this->member();
        $this->befriend($a, $b);
        $book = $this->book($a);
        $chat = $this->directChatId($a);
        $this->api($a, "/chat/{$chat}/send", ['audiobook_id' => $book->audiobook_id])->assertOk();

        $copyId = $this->api($b, "/content/{$book->audiobook_id}/save-copy")
            ->assertOk()
            ->assertJsonPath('data.is_mine', true)
            ->json('data.audiobook_id');
        $this->assertNotSame($book->audiobook_id, $copyId);

        $copy = Audiobook::find($copyId);
        $this->assertSame($b->caregiver_id, $copy->caregiver_id);
        $this->assertSame('private', $copy->visibility);
        $this->assertSame(2, $copy->pages()->count());

        // Saving again returns the same copy, and the card now says so.
        $this->api($b, "/content/{$book->audiobook_id}/save-copy")
            ->assertJsonPath('data.audiobook_id', $copyId);
        $this->assertSame(1, Audiobook::where('caregiver_id', $b->caregiver_id)->count());
        $this->api($b, "/chat/{$chat}/messages")->assertJsonPath('data.0.audiobook.in_my_library', true);

        // Editing my copy leaves the original alone.
        $this->api($b, "/content/{$copyId}/update", ['title' => 'Mine now'])->assertOk();
        $this->assertSame('Shared story', $book->fresh()->title);
    }

    public function test_hub_books_can_be_saved_but_unshared_ones_cannot(): void
    {
        $a = $this->member();
        $b = $this->member();
        $shared = $this->book($a, 'Hub story');
        $private = $this->book($a, 'Private story');

        $this->api($a, '/hub/create', ['audiobook_id' => $shared->audiobook_id])->assertOk();
        $this->api($b, '/hub/feed')->assertJsonPath('data.0.audiobook.in_my_library', false);

        $this->api($b, "/content/{$shared->audiobook_id}/save-copy")->assertOk();
        $this->api($b, '/hub/feed')->assertJsonPath('data.0.audiobook.in_my_library', true);

        $this->api($b, "/content/{$private->audiobook_id}/save-copy")->assertNotFound();
    }
}
