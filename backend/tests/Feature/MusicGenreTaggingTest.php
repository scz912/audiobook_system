<?php

namespace Tests\Feature;

use App\Models\MusicTrack;
use App\Services\GeminiService;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/* Genre + emotion tagging: what Gemini is told (the measured rhythm) and
   how its answer is cleaned. No database and no real Gemini call. */
class MusicGenreTaggingTest extends TestCase
{
    private const RHYTHM = [
        'seconds' => 120, 'bpm' => 96, 'bpm_estimate' => 96, 'beat' => 'steady',
        'beat_clarity' => 0.52, 'onsets_per_sec' => 3.4, 'loudness_db' => -18,
        'loudness_range_db' => 9, 'loud_jumps' => [92], 'brightness_hz' => 820,
    ];

    private function fakeGemini(array $answer): void
    {
        config(['services.gemini.key' => 'test-key', 'services.gemini.text_model' => 'test-model']);
        Http::fake([
            '*generativelanguage.googleapis.com/*' => Http::response([
                'candidates' => [['content' => ['parts' => [['text' => json_encode($answer)]]]]],
            ]),
        ]);
    }

    public function test_sends_the_measured_rhythm_and_reads_back_genre_and_emotions(): void
    {
        $this->fakeGemini([
            'genre' => 'jazz',
            'tags' => ['calm', 'Jazz', 'Curious', 'Soothing'],
            'tempo' => 'moderate',
            'summary' => 'Soft brushed drums and piano.',
            'sensory_notes' => 'A cymbal swell around 1:32.',
        ]);

        $result = (new GeminiService())->analyseMusic('bytes', 'audio/mp3', 'Night Walk', ['Calm', 'Happy'], self::RHYTHM);

        // Genre matched to the list's spelling; never repeated as a tag.
        $this->assertSame('Jazz', $result['genre']);
        $this->assertSame(['Calm', 'Curious', 'Soothing'], $result['tags']);
        $this->assertSame('moderate', $result['tempo']);

        Http::assertSent(function (Request $request) {
            $body = $request->data();
            $prompt = $body['contents'][0]['parts'][1]['text'];
            $schema = $body['generationConfig']['responseSchema'];
            return str_contains($prompt, 'steady and regular (clarity 0.52 of 1), about 96 BPM')
                && str_contains($prompt, 'Sudden loud jumps at: 1:32')
                && str_contains($prompt, 'Classical, Nature, Pop, Jazz')
                && $schema['properties']['genre']['enum'] === GeminiService::MUSIC_GENRES
                && in_array('genre', $schema['required'], true);
        });
    }

    public function test_works_without_measurements_and_drops_an_unknown_genre(): void
    {
        $this->fakeGemini([
            'genre' => 'Polka', 'tags' => ['Happy'], 'tempo' => 'upbeat',
            'summary' => '', 'sensory_notes' => '',
        ]);

        $result = (new GeminiService())->analyseMusic('bytes', 'audio/mp3', 'Song', ['Happy']);

        $this->assertNull($result['genre']);
        $this->assertSame(['Happy'], $result['tags']);
        Http::assertSent(fn (Request $r) => str_contains(
            $r->data()['contents'][0]['parts'][1]['text'],
            'No measurements are available',
        ));
    }

    public function test_the_genre_is_a_filter_tag_but_not_an_emotion_tag(): void
    {
        $track = new MusicTrack(['tags' => 'Calm,Gentle', 'genre' => 'Nature']);
        $this->assertSame(['Calm', 'Gentle'], $track->tagsArray());
        $this->assertSame(['Nature', 'Calm', 'Gentle'], $track->filterTags());

        $untyped = new MusicTrack(['tags' => 'Happy']);
        $this->assertSame(['Happy'], $untyped->filterTags());
    }
}
