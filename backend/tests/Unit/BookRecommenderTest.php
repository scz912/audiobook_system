<?php

namespace Tests\Unit;

use App\Services\BookRecommender;
use Carbon\Carbon;
use PHPUnit\Framework\TestCase;

class BookRecommenderTest extends TestCase
{
    private Carbon $now;

    protected function setUp(): void
    {
        parent::setUp();
        $this->now = Carbon::parse('2026-11-14 12:00:00');
    }

    private function book(string $id, string $topic, array $extra = []): array
    {
        return $extra + [
            'id' => $id, 'canon' => $id, 'title' => ucfirst($topic), 'category' => null,
            'topic' => $topic, 'tags' => null, 'difficulty' => 'easy', 'format' => 'linear',
            'language' => 'en', 'age_group' => null, 'status' => 'ready', 'genre' => null, 'emotions' => [],
        ];
    }

    private function read(string $child, string $book, bool $finished, float $daysAgo = 1, ?float $progress = null): array
    {
        return [
            'child' => $child, 'canon' => $book, 'completed' => $finished,
            'progress' => $progress ?? ($finished ? 1.0 : 0.1),
            'at' => $this->now->copy()->subHours((int) ($daysAgo * 24)),
        ];
    }

    private function recommend(array $books, array $sessions, array $context = []): array
    {
        return (new BookRecommender())->recommend($books, $sessions, $context + ['child' => 'me', 'limit' => 3], $this->now);
    }

    private function ids(array $recs): array
    {
        return array_column($recs, 'audiobook_id');
    }

    public function test_more_of_what_the_child_liked(): void
    {
        $books = [
            $this->book('cat1', 'my cat at home', ['tags' => 'animals']),
            $this->book('cat2', 'the cat and the dog', ['tags' => 'animals']),
            $this->book('cat3', 'a cat who sings', ['tags' => 'animals']),
            $this->book('space', 'rocket to the moon', ['tags' => 'space']),
        ];
        $recs = $this->recommend($books, [
            $this->read('me', 'cat1', true),
            $this->read('me', 'cat2', true),
        ], ['limit' => 2]);

        $this->assertSame('cat3', $recs[0]['audiobook_id']);
        $this->assertSame('like_book', $recs[0]['reason']['code']);
        $this->assertContains($recs[0]['reason']['params']['title'], ['My cat at home', 'The cat and the dog']);
        $this->assertTrue($recs[0]['new']);
    }

    public function test_books_like_ones_they_stopped_early_rank_lower(): void
    {
        $books = [
            $this->book('space1', 'rocket to the moon', ['tags' => 'space']),
            $this->book('space2', 'rocket to mars', ['tags' => 'space']),
            $this->book('farm', 'a day on the farm', ['tags' => 'farm']),
        ];
        $recs = $this->recommend($books, [
            $this->read('me', 'space1', false),
            $this->read('me', 'farm', false, 1, 0.5),
        ]);
        $order = $this->ids($recs);
        $this->assertLessThan(array_search('space2', $order), array_search('farm', $order));
    }

    public function test_children_who_liked_this_also_liked_that(): void
    {
        $books = [
            $this->book('a', 'dinosaur park'),
            $this->book('b', 'ocean waves', ['difficulty' => 'medium']),
            $this->book('c', 'city lights', ['difficulty' => 'medium']),
        ];
        $recs = $this->recommend($books, [
            $this->read('me', 'a', true),
            // Two other children loved both a and b; c was dropped.
            $this->read('k1', 'a', true), $this->read('k1', 'b', true), $this->read('k1', 'c', false),
            $this->read('k2', 'a', true), $this->read('k2', 'b', true), $this->read('k2', 'c', false),
        ]);

        $this->assertSame('b', $recs[0]['audiobook_id']);
        $this->assertSame('others_liked', $recs[0]['reason']['code']);
        $this->assertSame('Dinosaur park', $recs[0]['reason']['params']['title']);
        $this->assertNotNull($recs[0]['parts']['collaborative']);
    }

    public function test_a_new_child_gets_popular_books_and_mood_fits(): void
    {
        $books = [
            $this->book('loud', 'race day', ['genre' => 'Pop', 'emotions' => ['Energetic', 'Upbeat']]),
            $this->book('soft', 'good night moon', ['genre' => 'Ambient & Lullaby', 'emotions' => ['Calm', 'Soothing', 'Gentle']]),
            $this->book('hit', 'the big party', ['genre' => 'Pop', 'emotions' => ['Happy']]),
        ];
        $others = [
            $this->read('k1', 'hit', true), $this->read('k2', 'hit', true), $this->read('k3', 'hit', true),
            $this->read('k1', 'loud', false), $this->read('k2', 'loud', false),
        ];

        $sleepy = $this->recommend($books, $others, ['mood' => 'sleepy']);
        $this->assertSame('soft', $sleepy[0]['audiobook_id']);
        $this->assertSame('fits_mood', $sleepy[0]['reason']['code']);
        $this->assertNull($sleepy[0]['parts']['content']); // no history yet

        $noMood = $this->recommend($books, $others);
        $this->assertSame('hit', $noMood[0]['audiobook_id']);
        $this->assertSame('popular', $noMood[0]['reason']['code']);
    }

    public function test_music_taste_counts_when_given(): void
    {
        $books = [
            $this->book('jazzy', 'jazz cat', ['genre' => 'Jazz']),
            $this->book('techno', 'robot dance', ['genre' => 'Electronic']),
        ];
        $recs = $this->recommend($books, [], ['taste' => ['Electronic' => 0.9, 'Jazz' => 0.1]]);
        $this->assertSame('techno', $recs[0]['audiobook_id']);
        $this->assertSame('music_taste', $recs[0]['reason']['code']);
    }

    public function test_a_book_just_finished_waits_its_turn(): void
    {
        $books = [
            $this->book('fav', 'my cat at home', ['tags' => 'animals']),
            $this->book('next', 'my cat at school', ['tags' => 'animals']),
        ];
        $recs = $this->recommend($books, [$this->read('me', 'fav', true, 0.1)]);
        $this->assertSame('next', $recs[0]['audiobook_id']);
    }

    public function test_the_list_is_varied_and_unfinished_books_are_left_out(): void
    {
        $books = [
            $this->book('cat1', 'my cat', ['tags' => 'animals']),
            $this->book('cat1b', 'my cat', ['tags' => 'animals']),
            $this->book('cat1c', 'my cat', ['tags' => 'animals']),
            $this->book('sea', 'under the sea', ['tags' => 'ocean']),
            $this->book('wip', 'my cat', ['tags' => 'animals', 'status' => 'processing']),
        ];
        $recs = $this->recommend($books, [], ['limit' => 2]);
        $ids = $this->ids($recs);
        $this->assertCount(2, $ids);
        $this->assertContains('sea', $ids); // not two copies of the same cat book
        $this->assertNotContains('wip', $ids);
    }

    public function test_difficulty_a_little_above_what_they_finish(): void
    {
        $books = [
            $this->book('e1', 'apple', ['difficulty' => 'easy']),
            $this->book('e2', 'banana', ['difficulty' => 'easy']),
            $this->book('m1', 'cherry', ['difficulty' => 'medium']),
            $this->book('h1', 'durian', ['difficulty' => 'hard']),
        ];
        $recs = $this->recommend($books, [
            $this->read('me', 'e1', true), $this->read('me', 'e2', true),
        ]);
        $this->assertEqualsWithDelta(0.8, $recs[array_search('m1', $this->ids($recs))]['parts']['fit'], 0.001);
        $this->assertLessThan(
            array_search('h1', $this->ids($recs)) === false ? 99 : array_search('h1', $this->ids($recs)),
            array_search('m1', $this->ids($recs))
        );
    }
}
