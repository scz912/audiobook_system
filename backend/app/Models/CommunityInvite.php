<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class CommunityInvite extends Model
{
    use HasUuids;

    protected $table = 'community_invites';
    protected $primaryKey = 'invite_id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'inviter_id',
        'code',
        'email',
        'status',
        'accepted_by',
    ];

    public function uniqueIds(): array
    {
        return ['invite_id'];
    }

    public function inviter(): BelongsTo
    {
        return $this->belongsTo(Caregiver::class, 'inviter_id', 'caregiver_id');
    }
}
