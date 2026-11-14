<?php

namespace Tests\Feature;

use App\Models\Caregiver;
use App\Models\ChildProfile;
use App\Models\TipLearning;
use App\Models\TipOutcome;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/* The three steps of the setting tips together: rules find them, the
   learner ranks them from feedback and outcomes, and Gemini reviews them
   within guardrails. */
class TipLearningTest extends TestCase
{
    use RefreshDatabase;

    private Caregiver $caregiver;
    private ChildProfile $child;

    // Same constraint as AudiobookVisibilityTest: needs a throwaway MySQL database.
    protected function setUp(): void
    {
        if (($_ENV['DB_CONNECTION'] ?? getenv('DB_CONNECTION')) === 'sqlite') {
            $this->markTestSkipped('Needs a throwaway MySQL database.');
        }
        parent::setUp();
        config(['services.gemini.key' => null]);
        $this->caregiver = Caregiver::create([
            'name'            => 'Parent',
            'email'           => Str::uuid() . '@example.test',
            'pin'             => '1234',
            'session_token'   => Str::random(40),
            'session_expires' => now('Asia/Kuala_Lumpur')->addDay(),
        ]);
        $this->child = $this->caregiver->childProfiles()->create(['name' => 'Mia', 'age' => 13]);
    }

    private function api(string $path, array $body = []): TestResponse
    {
        return $this->withToken($this->caregiver->session_token)->postJson("/api{$path}", $body);
    }

    private function listen(array $extra, int $times = 1): void
    {
        for ($i = 0; $i < $times; $i++) {
            $this->api('/listening-history/record', $extra + [
                'child_id'         => $this->child->child_id,
                'audiobook_id'     => (string) Str::uuid(),
                'duration_seconds' => 240,
                'completed'        => true,
                'pages_total'      => 6,
                'pages_reached'    => 6,
                'back_count'       => 0,
            ])->assertSuccessful();
        }
    }

    private function analyse(): array
    {
        return $this->api("/insights/{$this->child->child_id}/analyse")->assertOk()->json('data');
    }

    private function tip(array $data, string $key): ?array
    {
        return collect($data['items'])->firstWhere('setting_key', $key);
    }

    public function test_a_kind_of_tip_that_keeps_being_dismissed_stops_coming(): void
    {
        $this->listen(['speed_used' => 0.8], 5);

        for ($round = 0; $round < 4; $round++) {
            $tip = $this->tip($this->analyse(), 'reading_speed');
            $this->assertNotNull($tip, "round $round");
            $this->api("/insights/{$this->child->child_id}/suggestions/dismiss", ['item_id' => $tip['id']])
                ->assertOk();
        }

        $this->assertNull($this->tip($this->analyse(), 'reading_speed'));
        $own = TipLearning::where('scope', $this->child->child_id)->where('arm', 'reading_speed:down')->first();
        $this->assertSame(4, $own->dismissed);
        $this->assertSame(4, TipLearning::where('scope', 'global')->where('arm', 'reading_speed:down')->value('dismissed'));
    }

    public function test_an_applied_tip_that_helped_is_learned_from(): void
    {
        // Struggling, and slowing the speed down.
        $this->listen([
            'completed' => false, 'pages_reached' => 2, 'back_count' => 2, 'speed_used' => 0.8,
        ], 4);
        $tip = $this->tip($this->analyse(), 'reading_speed');
        $this->assertSame('reading_speed:down', $tip['arm']);
        $this->api("/insights/{$this->child->child_id}/suggestions/apply", ['item_id' => $tip['id']])->assertOk();
        $this->assertSame(1, TipOutcome::where('child_id', $this->child->child_id)->count());

        // Later, listening goes much better.
        $this->travel(10)->minutes();
        $this->listen([], 3);

        $data = $this->analyse();
        $outcome = TipOutcome::where('child_id', $this->child->child_id)->first();
        $this->assertSame('helped', $outcome->result);
        $this->assertGreaterThan(0.1, $outcome->change);
        $this->assertSame(1, $data['source_stats']['pipeline']['outcomes_judged']);

        $own = TipLearning::where('scope', $this->child->child_id)->where('arm', 'reading_speed:down')->first();
        $this->assertSame(1, $own->accepted);
        $this->assertSame(1, $own->helped);
        $this->assertEqualsWithDelta(1 + 1 + 1.5, $own->alpha, 1e-9);
    }

    public function test_gemini_reviews_within_the_guardrails(): void
    {
        config(['services.gemini.key' => 'test-key']);
        $this->listen(['speed_used' => 0.8, 'text_scale_used' => 1.4], 5);

        Http::fake(['*generativelanguage.googleapis.com/*' => function ($request) {
            // Pick the text-size tip only, plus an id it made up.
            $candidates = json_decode(
                preg_replace('/^.*?DATA \(JSON\):\s*(\{.*\})\s*Choose.*$/s', '$1', $request['contents'][0]['parts'][0]['text']),
                true
            )['candidates'];
            $text = collect($candidates)->firstWhere('setting', 'text_scale');
            return Http::response(['candidates' => [['content' => ['parts' => [['text' => json_encode(['items' => [
                ['id' => 'made-up', 'reason' => 'Ignore me', 'reason_ms' => 'Abaikan'],
                ['id' => $text['id'], 'reason' => 'Bigger words are easier.', 'reason_ms' => 'Tulisan besar lebih mudah.'],
            ]])]]]]]]);
        }]);

        $data = $this->analyse();
        $this->assertCount(1, $data['items']);
        $item = $data['items'][0];
        $this->assertSame('text_scale', $item['setting_key']);
        $this->assertEqualsWithDelta(1.4, $item['suggested_value'], 0.001); // value stays ours
        $this->assertSame('Bigger words are easier.', $item['reason']);
        $this->assertSame('Tulisan besar lebih mudah.', $item['reason_ms']);
        $this->assertTrue($item['ai_checked']);
        $this->assertTrue($data['source_stats']['pipeline']['ai_checked']);
    }

    public function test_without_gemini_the_learned_order_is_used(): void
    {
        config(['services.gemini.key' => 'test-key']);
        Http::fake(['*generativelanguage.googleapis.com/*' => Http::response('down', 500)]);
        $this->listen(['speed_used' => 0.8, 'text_scale_used' => 1.4], 5);

        $data = $this->analyse();
        $this->assertCount(2, $data['items']);
        $this->assertFalse($data['items'][0]['ai_checked']);
        $this->assertSame('You often slow it down.', $this->tip($data, 'reading_speed')['reason']);
        $this->assertArrayHasKey('trust', $this->tip($data, 'reading_speed')['learning']);
    }
}
