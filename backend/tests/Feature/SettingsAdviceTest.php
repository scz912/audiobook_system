<?php

namespace Tests\Feature;

use App\Models\Caregiver;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

class SettingsAdviceTest extends TestCase
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

    private function api(Caregiver $c, string $path, array $body = []): TestResponse
    {
        return $this->withToken($c->session_token)->postJson("/api{$path}", $body);
    }

    // Sessions saved through the app's own endpoint turn into tips, with no AI.
    public function test_recorded_choices_become_tips_without_ai(): void
    {
        config(['services.gemini.key' => null]);
        $caregiver = Caregiver::create([
            'name'            => 'Parent',
            'email'           => Str::uuid() . '@example.test',
            'pin'             => '1234',
            'session_token'   => Str::random(40),
            'session_expires' => now('Asia/Kuala_Lumpur')->addDay(),
        ]);
        $child = $caregiver->childProfiles()->create(['name' => 'Mia', 'age' => 12]);

        for ($i = 0; $i < 5; $i++) {
            $this->api($caregiver, '/listening-history/record', [
                'child_id'         => $child->child_id,
                'audiobook_id'     => (string) Str::uuid(),
                'duration_seconds' => 240,
                'completed'        => true,
                'pages_total'      => 6,
                'pages_reached'    => 6,
                'back_count'       => 0,
                'speed_used'       => 0.8,
                'text_scale_used'  => 1.3,
            ])->assertSuccessful();
        }

        $data = $this->api($caregiver, "/insights/{$child->child_id}/analyse")
            ->assertOk()
            ->json('data');

        $byKey = collect($data['items'])->keyBy('setting_key');
        $this->assertEqualsWithDelta(0.8, $byKey['reading_speed']['suggested_value'], 0.001);
        $this->assertEqualsWithDelta(1.3, $byKey['text_scale']['suggested_value'], 0.001);
        $this->assertSame('pending', $byKey['reading_speed']['status']);
        $this->assertNotEmpty($byKey['reading_speed']['reason_ms']);
        $this->assertSame('normal', $data['confidence']);
        $this->assertSame(5, $data['source_stats']['sessions_count']);

        // Applying one writes it to the child's settings.
        $this->api($caregiver, "/insights/{$child->child_id}/suggestions/apply", [
            'item_id' => $byKey['reading_speed']['id'],
        ])->assertOk();
        $this->assertEqualsWithDelta(0.8, (float) $child->fresh()->childSettings->reading_speed, 0.001);
    }

    public function test_bad_signal_values_are_rejected(): void
    {
        $caregiver = Caregiver::create([
            'name'            => 'Parent',
            'email'           => Str::uuid() . '@example.test',
            'pin'             => '1234',
            'session_token'   => Str::random(40),
            'session_expires' => now('Asia/Kuala_Lumpur')->addDay(),
        ]);
        $child = $caregiver->childProfiles()->create(['name' => 'Mia', 'age' => 12]);

        $this->api($caregiver, '/listening-history/record', [
            'child_id'     => $child->child_id,
            'audiobook_id' => (string) Str::uuid(),
            'speed_used'   => 5,
            'voice_used'   => 'robot',
        ])->assertStatus(422);
    }
}
