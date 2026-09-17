<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class HubPost extends Model
{
    use HasUuids;

    protected $table = 'hub_posts';
    protected $primaryKey = 'post_id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'audiobook_id',
        'shared_by',
        'caption',
        'include_music',
    ];

    protected $casts = [
        'include_music' => 'boolean',
    ];

    public function uniqueIds(): array
    {
        return ['post_id'];
    }

    public function audiobook(): BelongsTo
    {
        return $this->belongsTo(Audiobook::class, 'audiobook_id', 'audiobook_id');
    }

    public function author(): BelongsTo
    {
        return $this->belongsTo(Caregiver::class, 'shared_by', 'caregiver_id');
    }

    public function likes(): HasMany
    {
        return $this->hasMany(HubLike::class, 'post_id', 'post_id');
    }

    public function comments(): HasMany
    {
        return $this->hasMany(HubComment::class, 'post_id', 'post_id');
    }
}
