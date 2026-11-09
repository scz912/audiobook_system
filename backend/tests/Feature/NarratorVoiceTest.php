<?php

namespace Tests\Feature;

use App\Models\Caregiver;
use App\Models\ChildSettings;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

class NarratorVoiceTest extends TestCase
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

    private function caregiver(): Caregiver
    {
        return Caregiver::create([
            'name'            => 'Parent',
            'email'           => Str::uuid() . '@example.test',
            'pin'             => '1234',
            'session_token'   => Str::random(40),
            'session_expires' => now('Asia/Kuala_Lumpur')->addDay(),
        ]);
    }

    private function api(Caregiver $c, string $path, array $body = []): TestResponse
    {
        return $this->withToken($c->session_token)->postJson("/api{$path}", $body);
    }

    public function test_a_child_can_use_either_of_the_two_voices_only(): void
    {
        $caregiver = $this->caregiver();
        $child = $caregiver->childProfiles()->create(['name' => 'Mia', 'age' => 7]);
        $path = "/child-profiles/{$child->child_id}/settings/update";

        $this->api($caregiver, $path, ['narrator_voice' => 'warm_male'])->assertOk();
        $this->api($caregiver, $path, ['narrator_voice' => 'calm_female'])->assertOk();
        // Retired voices are no longer offered.
        $this->api($caregiver, $path, ['narrator_voice' => 'friendly_child'])->assertStatus(422);
    }

    public function test_saved_retired_voices_move_to_the_nearest_of_the_two(): void
    {
        $caregiver = $this->caregiver();
        $made = [];
        foreach (['gentle_female', 'friendly_child', 'soothing_elder', 'warm_male'] as $i => $voice) {
            $child = $caregiver->childProfiles()->create(['name' => "Kid $i", 'age' => 7]);
            $made[$voice] = ChildSettings::create(['child_id' => $child->child_id, 'narrator_voice' => $voice]);
        }

        (require database_path('migrations/2026_11_10_000002_keep_two_narrator_voices.php'))->up();

        $this->assertSame('calm_female', $made['gentle_female']->fresh()->narrator_voice);
        $this->assertSame('calm_female', $made['friendly_child']->fresh()->narrator_voice);
        $this->assertSame('warm_male', $made['soothing_elder']->fresh()->narrator_voice);
        $this->assertSame('warm_male', $made['warm_male']->fresh()->narrator_voice);
    }
}
