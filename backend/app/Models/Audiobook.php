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

    /* Books in this caregiver's library: their own, plus the shared books
       from before books had owners (the only public ones). New books are
       always private, so nothing a caregiver makes appears for anyone else. */
    public function scopeVisibleTo($query, ?string $caregiverId)
    {
        return $query->where(function ($q) use ($caregiverId) {
            $q->where('visibility', 'public');
            if ($caregiverId) {
                $q->orWhere('caregiver_id', $caregiverId);
            }
        });
    }

    /* Books this caregiver can change or delete: only their own. Books with
       no owner used to be editable by everyone, so deleting one removed it
       for every family; each caregiver now has their own copy instead (see
       the give_each_caregiver_own_copy_of_shared_books migration). */
    public function scopeEditableBy($query, ?string $caregiverId)
    {
        if (!$caregiverId) {
            return $query->whereRaw('1 = 0');
        }
        return $query->where('caregiver_id', $caregiverId);
    }

    /* Books this caregiver can open in the player: their library, plus any
       book shared in the community hub once they're a member. */
    public function scopeOpenableBy($query, ?Caregiver $caregiver)
    {
        return $query->where(function ($q) use ($caregiver) {
            $q->visibleTo($caregiver?->caregiver_id);
            if ($caregiver?->is_community_member) {
                $q->orWhereIn('audiobook_id', HubPost::query()
                    ->whereNotNull('audiobook_id')
                    ->select('audiobook_id'));
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