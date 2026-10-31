<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Str;

class Audiobook extends Model
{
    use HasFactory;

    protected $table = 'audiobooks';
    protected $primaryKey = 'audiobook_id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'audiobook_id',
        'caregiver_id',
        'title',
        'author',
        'description',
        'topic',
        'category',
        'difficulty',
        'type',
        'book_format',
        'content_text',
        'audio_file',
        'video_file',
        'source_file',
        'cover_image',
        'duration_minutes',
        'language',
        'age_group',
        'tags',
        'is_generated',
        'is_user_uploaded',
        'status',
        'visibility',
        'track_id',
        'bgm_volume',
    ];

    protected $casts = [
        'is_generated' => 'boolean',
        'is_user_uploaded' => 'boolean',
        'duration_minutes' => 'integer',
        'bgm_volume' => 'integer',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
    ];

    protected static function boot()
    {
        parent::boot();

        static::creating(function ($model) {
            if (!$model->audiobook_id) {
                $model->audiobook_id = (string) Str::uuid();
            }
        });
    }

    /* Books this caregiver can see: everything public plus their own private
       ones. Other caregivers' private books stay hidden. */
    public function scopeVisibleTo($query, ?string $caregiverId)
    {
        return $query->where(function ($q) use ($caregiverId) {
            $q->where('visibility', 'public');
            if ($caregiverId) {
                $q->orWhere('caregiver_id', $caregiverId);
            }
        });
    }

    /* Books this caregiver can change: their own, plus older books from
       before books had owners. */
    public function scopeEditableBy($query, ?string $caregiverId)
    {
        return $query->where(function ($q) use ($caregiverId) {
            $q->whereNull('caregiver_id');
            if ($caregiverId) {
                $q->orWhere('caregiver_id', $caregiverId);
            }
        });
    }

    public function isOwnedBy(?string $caregiverId): bool
    {
        return $this->caregiver_id !== null && $this->caregiver_id === $caregiverId;
    }

    public function musicTrack(): BelongsTo
    {
        return $this->belongsTo(MusicTrack::class, 'track_id', 'track_id');
    }

    public function listeningHistory(): HasMany
    {
        return $this->hasMany(ListeningHistory::class, 'audiobook_id', 'audiobook_id');
    }

    public function pages(): HasMany
    {
        // Split pages share a page_number; keep their two versions in order.
        return $this->hasMany(AudiobookPage::class, 'audiobook_id', 'audiobook_id')
            ->orderBy('page_number')
            ->orderBy('branch_index');
    }
}