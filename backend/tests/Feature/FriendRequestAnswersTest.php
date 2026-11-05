<?php

namespace Tests\Feature;

use App\Models\Caregiver;
use App\Models\CommunityInvite;
use App\Models\Friendship;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

class FriendRequestAnswersTest extends TestCase
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

    private function member(string $name = 'Family', bool $member = true): Caregiver
    {
        return Caregiver::create([
            'name'                => $name,
            'email'               => Str::uuid() . '@example.test',
            'pin'                 => '1234',
            'session_token'       => Str::random(40),
            'session_expires'     => now('Asia/Kuala_Lumpur')->addDay(),
            'is_community_member' => $member,
        ]);
    }

    private function api(Caregiver $caregiver, string $path, array $body = []): TestResponse
    {
        return $this->withToken($caregiver->session_token)->postJson("/api{$path}", $body);
    }

    private function sendRequest(Caregiver $from, Caregiver $to): string
    {
        $this->api($from, '/friends/request', ['caregiver_id' => $to->caregiver_id])->assertOk();
        return $this->api($to, '/friends/pending')->json('data.0.friendship_id');
    }

    public function test_sender_sees_an_accept_until_they_mark_it_seen(): void
    {
        $sender = $this->member();
        $other = $this->member('Aisyah');
        $id = $this->sendRequest($sender, $other);

        $this->api($sender, '/friends/updates')->assertJsonCount(0, 'data');
        $this->api($other, '/friends/respond', ['friendship_id' => $id, 'action' => 'accept'])->assertOk();

        $this->api($sender, '/friends/updates')
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.status', 'accepted')
            ->assertJsonPath('data.0.person.name', 'Aisyah');

        $this->api($sender, '/friends/updates/seen')->assertOk();
        $this->api($sender, '/friends/updates')->assertJsonCount(0, 'data');
        // Still friends after seeing it.
        $this->api($sender, '/friends')->assertJsonPath('data.0.caregiver_id', $other->caregiver_id);
    }

    public function test_sender_sees_a_decline_and_can_ask_again_afterwards(): void
    {
        $sender = $this->member();
        $other = $this->member();
        $id = $this->sendRequest($sender, $other);

        $this->api($other, '/friends/respond', ['friendship_id' => $id, 'action' => 'decline'])->assertOk();

        $this->api($sender, '/friends/updates')->assertJsonPath('data.0.status', 'declined');
        // A declined request isn't a friendship or a pending request.
        $this->api($sender, '/friends')->assertJsonCount(0, 'data');
        $this->api($other, '/friends/pending')->assertJsonCount(0, 'data');

        $this->api($sender, '/friends/updates/seen')->assertOk();
        $this->assertSame(0, Friendship::count());

        $this->api($sender, '/friends/request', ['caregiver_id' => $other->caregiver_id])->assertOk();
    }

    public function test_can_ask_again_even_before_seeing_the_decline(): void
    {
        $sender = $this->member();
        $other = $this->member();
        $id = $this->sendRequest($sender, $other);
        $this->api($other, '/friends/respond', ['friendship_id' => $id, 'action' => 'decline']);

        $this->api($sender, '/friends/request', ['caregiver_id' => $other->caregiver_id])->assertOk();
        $this->api($other, '/friends/pending')->assertJsonCount(1, 'data');
    }

    public function test_answers_are_only_shown_to_the_sender(): void
    {
        $sender = $this->member();
        $other = $this->member();
        $id = $this->sendRequest($sender, $other);
        $this->api($other, '/friends/respond', ['friendship_id' => $id, 'action' => 'accept']);

        $this->api($other, '/friends/updates')->assertJsonCount(0, 'data');
        // Marking my own updates seen doesn't touch someone else's.
        $this->api($other, '/friends/updates/seen');
        $this->api($sender, '/friends/updates')->assertJsonCount(1, 'data');
    }

    public function test_new_member_from_an_invite_sees_everyone_to_befriend(): void
    {
        $inviter = $this->member('Inviter');
        $stranger = $this->member('Stranger');
        $this->member('Not joined', member: false);
        $newcomer = $this->member('Newcomer', member: false);
        CommunityInvite::create([
            'inviter_id' => $inviter->caregiver_id,
            'code'       => 'WELCOME1',
            'status'     => 'pending',
        ]);

        $this->api($newcomer, '/community/invites/accept', ['code' => 'WELCOME1'])->assertOk();

        // The "Families in the community" list after joining.
        $people = collect($this->api($newcomer, '/friends/search', ['search' => ''])->json('data'))
            ->pluck('relation', 'name');
        $this->assertSame(['Inviter' => 'friends', 'Stranger' => 'none'], $people->all());
    }
}
