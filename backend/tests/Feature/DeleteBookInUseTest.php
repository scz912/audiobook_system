<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\ContentManagementController;
use App\Models\Audiobook;
use App\Models\Caregiver;
use App\Models\ChildProfile;
use App\Models\ListeningHistory;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/* FR8: a book one of my children is partway through can't be deleted. */
class DeleteBookInUseTest extends TestCase
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

    private function caregiver(): Caregiver
    {
        return Caregiver::create([
            'name'            => 'Caregiver',
            'email'           => Str::uuid() . '@example.test',
            'pin'             => '1234',
            'session_token'   => Str::random(40),
            'session_expires' => now('Asia/Kuala_Lumpur')->addDay(),
        ]);
    }

    private function child(Caregiver $caregiver): ChildProfile
    {
        return ChildProfile::create(['caregiver_id' => $caregiver->caregiver_id, 'name' => 'Aina', 'age' => 7]);
    }

    private function book(Caregiver $owner): Audiobook
    {
        return Audiobook::create([
            'caregiver_id' => $owner->caregiver_id,
            'title'        => 'A story',
            'visibility'   => 'private',
        ]);
    }

    private function listened(ChildProfile $child, Audiobook $book, bool $completed, int $daysAgo = 0): void
    {
        $row = ListeningHistory::create([
            'child_id'     => $child->child_id,
            'audiobook_id' => $book->audiobook_id,
            'completed'    => $completed,
        ]);
        $row->created_at = now()->subDays($daysAgo);
        $row->save();
    }

    private function deleteBook(Caregiver $caregiver, Audiobook $book): TestResponse
    {
        return $this->withToken($caregiver->session_token)
            ->postJson("/api/content/{$book->audiobook_id}/delete");
    }

    public function test_a_book_my_child_is_partway_through_cannot_be_deleted(): void
    {
        $me = $this->caregiver();
        $book = $this->book($me);
        $this->listened($this->child($me), $book, completed: false);

        $this->deleteBook($me, $book)
            ->assertStatus(409)
            ->assertJsonPath('error_code', 'IN_USE')
            ->assertJsonPath('message', ContentManagementController::IN_USE_MESSAGE);
        $this->assertDatabaseHas('audiobooks', ['audiobook_id' => $book->audiobook_id]);
    }

    public function test_a_finished_book_can_be_deleted(): void
    {
        $me = $this->caregiver();
        $book = $this->book($me);
        $child = $this->child($me);
        $this->listened($child, $book, completed: false, daysAgo: 1);
        $this->listened($child, $book, completed: true);

        $this->deleteBook($me, $book)->assertOk();
        $this->assertDatabaseMissing('audiobooks', ['audiobook_id' => $book->audiobook_id]);
    }

    public function test_a_book_left_unfinished_long_ago_can_be_deleted(): void
    {
        $me = $this->caregiver();
        $book = $this->book($me);
        $this->listened($this->child($me), $book, completed: false, daysAgo: 30);

        $this->deleteBook($me, $book)->assertOk();
    }

    public function test_a_book_never_played_can_be_deleted(): void
    {
        $me = $this->caregiver();
        $book = $this->book($me);
        $this->child($me);

        $this->deleteBook($me, $book)->assertOk();
    }
}
