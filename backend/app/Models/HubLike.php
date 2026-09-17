<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class HubLike extends Model
{
    use HasUuids;

    protected $table = 'hub_likes';
    protected $primaryKey = 'id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'post_id',
        'caregiver_id',
    ];

    public function uniqueIds(): array
    {
        return ['id'];
    }

    public function post(): BelongsTo
    {
        return $this->belongsTo(HubPost::class, 'post_id', 'post_id');
    }
}
