<?php

namespace Tests\Feature;

use App\Models\Caregiver;
use App\Models\ChildProfile;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class IndependentAccountTest extends TestCase
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

    public function test_a_teenager_on_their_own_gets_an_independent_account_and_a_profile(): void
    {
        $resp = $this->postJson('/api/auth/register', [
            'name'         => 'Aiman',
            'email'        => 'aiman@example.test',
            'pin'          => '1234',
            'account_type' => 'independent',
            'age'          => 15,
        ])->assertOk()
            ->assertJsonPath('data.caregiver.account_type', 'independent');

        $caregiver = Caregiver::where('email', 'aiman@example.test')->first();
        $this->assertSame('independent', $caregiver->account_type);

        // Their own profile, so moods and listening history have somewhere to go.
        $profile = ChildProfile::where('caregiver_id', $caregiver->caregiver_id)->sole();
        $this->assertSame('Aiman', $profile->name);
        $this->assertSame(15, $profile->age);

        $token = $resp->json('data.session_token') ?? $caregiver->fresh()->session_token;
        $this->withToken($token)->postJson('/api/auth/me')
            ->assertJsonPath('data.account_type', 'independent');
    }

    public function test_a_parent_account_is_a_caregiver_with_no_profile_yet(): void
    {
        $this->postJson('/api/auth/register', [
            'name'  => 'Parent',
            'email' => 'parent@example.test',
            'pin'   => '1234',
        ])->assertOk()
            ->assertJsonPath('data.caregiver.account_type', 'caregiver');

        $caregiver = Caregiver::where('email', 'parent@example.test')->first();
        $this->assertSame(0, ChildProfile::where('caregiver_id', $caregiver->caregiver_id)->count());
    }

    public function test_unknown_account_type_is_rejected(): void
    {
        $this->postJson('/api/auth/register', [
            'name'         => 'X',
            'pin'          => '1234',
            'account_type' => 'admin',
        ])->assertStatus(422);
        $this->assertSame(0, Caregiver::count());
    }
}
