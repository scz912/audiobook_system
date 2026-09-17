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
}
