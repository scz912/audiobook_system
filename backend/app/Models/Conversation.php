<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Conversation extends Model
{
    use HasUuids;

    protected $table = 'conversations';
    protected $primaryKey = 'conversation_id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'type',
        'title',
        'created_by',
    ];

    public function uniqueIds(): array
    {
        return ['conversation_id'];
    }

    public function participants(): HasMany
    {
        return $this->hasMany(ConversationParticipant::class, 'conversation_id', 'conversation_id');
    }

    public function messages(): HasMany
    {
        return $this->hasMany(Message::class, 'conversation_id', 'conversation_id');
    }

    // The one-to-one chat these two people share, or null if there isn't one.
    public static function findDirect(string $a, string $b): ?self
    {
        $aConvs = ConversationParticipant::where('caregiver_id', $a)->pluck('conversation_id');
        $bConvs = ConversationParticipant::where('caregiver_id', $b)->pluck('conversation_id');
        $shared = $aConvs->intersect($bConvs);
        if ($shared->isEmpty()) {
            return null;
        }
        return static::whereIn('conversation_id', $shared)
            ->where('type', 'direct')
            ->first();
    }

    /* The one-to-one chat between [startedBy] and [other], made if it doesn't
       exist yet. Friends get one as soon as they connect, so every friend is
       in the chat list without first visiting their profile. */
    public static function openDirect(string $startedBy, string $other): self
    {
        $existing = static::findDirect($startedBy, $other);
        if ($existing) {
            return $existing;
        }
        $conv = static::create([
            'type'       => 'direct',
            'created_by' => $startedBy,
        ]);
        ConversationParticipant::firstOrCreate(
            ['conversation_id' => $conv->conversation_id, 'caregiver_id' => $startedBy],
            ['role' => 'admin']
        );
        ConversationParticipant::firstOrCreate(
            ['conversation_id' => $conv->conversation_id, 'caregiver_id' => $other],
            ['role' => 'member']
        );
        return $conv;
    }
}
