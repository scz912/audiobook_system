<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Friendship extends Model
{
    use HasUuids;

    protected $table = 'friendships';
    protected $primaryKey = 'friendship_id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'requester_id',
        'addressee_id',
        'status',
    ];

    public function uniqueIds(): array
    {
        return ['friendship_id'];
    }

    public function requester(): BelongsTo
    {
        return $this->belongsTo(Caregiver::class, 'requester_id', 'caregiver_id');
    }

    public function addressee(): BelongsTo
    {
        return $this->belongsTo(Caregiver::class, 'addressee_id', 'caregiver_id');
    }
}
