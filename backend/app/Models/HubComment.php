<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class HubComment extends Model
{
    use HasUuids;

    protected $table = 'hub_comments';
    protected $primaryKey = 'comment_id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'post_id',
        'caregiver_id',
        'body',
    ];

    public function uniqueIds(): array
    {
        return ['comment_id'];
    }

    public function post(): BelongsTo
    {
        return $this->belongsTo(HubPost::class, 'post_id', 'post_id');
    }

    public function caregiver(): BelongsTo
    {
        return $this->belongsTo(Caregiver::class, 'caregiver_id', 'caregiver_id');
    }
}
