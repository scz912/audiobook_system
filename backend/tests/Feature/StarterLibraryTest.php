<?php

namespace Tests\Feature;

use App\Models\Audiobook;
use App\Models\AudiobookPage;
use App\Models\Caregiver;
use App\Services\StarterLibrary;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

/* Every account starts with its own copy of the demo account's starter
   books, so no library opens empty. */
class StarterLibraryTest extends TestCase
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

    private function account(string $name): Caregiver
    {
        return Caregiver::create([
            'name'            => $name,
            'email'           => Str::uuid() . '@example.test',
            'pin'             => '1234',
            'session_token'   => Str::random(40),
            'session_expires' => now('Asia/Kuala_Lumpur')->addDay(),
        ]);
    }

    private function book(Caregiver $owner, string $title, string $format = 'linear', string $status = 'available'): Audiobook
    {
        $book = Audiobook::create([
            'caregiver_id' => $owner->caregiver_id,
            'title'        => $title,
            'book_format'  => $format,
            'visibility'   => 'private',
            'status'       => $status,
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

    // The demo account: the three linear titles, four interactive books
    // (only the oldest three count) and one still making pictures.
    private function demo(): Caregiver
    {
        $demo = $this->account('Demo');
        foreach (StarterLibrary::LINEAR_TITLES as $title) {
            $this->book($demo, $title);
        }
        $this->book($demo, 'Not a starter');
        foreach (['Pick a pet', 'Which path?', 'Rainy day'] as $i => $title) {
            $this->travel($i + 1)->minutes();
            $this->book($demo, $title, 'interactive');
        }
        $this->travel(10)->minutes();
        $this->book($demo, 'Too new', 'interactive');
        $this->book($demo, 'Still drawing', 'interactive', 'processing');
        return $demo;
    }

    public function test_starters_are_the_three_titles_and_the_oldest_three_interactive(): void
    {
        $this->demo();
        $titles = StarterLibrary::sources()->pluck('title')->all();
        $this->assertSame([
            '3 Kids playing ball together',
            'A tree with emotion',
            'Rahsia di Sebalik Kulit Manggis',
            'Pick a pet',
            'Which path?',
            'Rainy day',
        ], $titles);
    }

    public function test_a_new_account_gets_its_own_private_copies(): void
    {
        $demo = $this->demo();

        $this->postJson('/api/auth/register', [
            'name'  => 'New family',
            'email' => 'new@example.test',
            'pin'   => '1234',
        ])->assertOk();
        $me = Caregiver::where('email', 'new@example.test')->first();

        $mine = Audiobook::where('caregiver_id', $me->caregiver_id)->get();
        $this->assertCount(6, $mine);
        $this->assertSame(3, $mine->where('book_format', 'interactive')->count());
        foreach ($mine as $copy) {
            $this->assertSame('private', $copy->visibility);
            $this->assertNotNull($copy->source_audiobook_id);
            $this->assertSame(2, $copy->pages()->count());
        }
        // The demo account's books are untouched.
        $this->assertSame(9, Audiobook::where('caregiver_id', $demo->caregiver_id)->count());
    }

    public function test_giving_again_adds_nothing_and_skips_books_they_already_have(): void
    {
        $this->demo();
        $other = $this->account('Old family');
        // Already has one, say from an older migration's copy.
        $this->book($other, 'A tree with emotion');

        $this->assertSame(5, StarterLibrary::giveTo($other->caregiver_id));
        $this->assertSame(0, StarterLibrary::giveTo($other->caregiver_id));
        $this->assertSame(6, Audiobook::where('caregiver_id', $other->caregiver_id)->count());
    }

    public function test_no_demo_books_means_sign_up_still_works(): void
    {
        $this->postJson('/api/auth/register', [
            'name'  => 'First ever',
            'email' => 'first@example.test',
            'pin'   => '1234',
        ])->assertOk();
        $this->assertSame(0, Audiobook::count());
    }
}
