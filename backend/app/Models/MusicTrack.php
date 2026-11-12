<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

class MusicTrack extends Model
{
    protected $table = 'music_tracks';
    protected $primaryKey = 'track_id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'track_id', 'caregiver_id', 'title', 'composer', 'file_path',
        'tags', 'genre', 'tempo', 'bpm', 'beat', 'duration_secs', 'ai_summary',
        'sensory_notes', 'status',
    ];

    protected $casts = [
        'duration_secs' => 'integer',
        'bpm'           => 'integer',
    ];

    protected static function boot(): void
    {
        parent::boot();
        static::creating(function ($model) {
            if (!$model->track_id) {
                $model->track_id = (string) Str::uuid();
            }
        });
    }

    /* Active tracks this caregiver can use: the built-in ones plus their
       own uploads. Other caregivers' uploads stay hidden. */
    public function scopeVisibleTo($query, ?string $caregiverId)
    {
        return $query->where('status', 'active')
            ->where(function ($q) use ($caregiverId) {
                $q->whereNull('caregiver_id');
                if ($caregiverId) {
                    $q->orWhere('caregiver_id', $caregiverId);
                }
            });
    }

    // Every emotion tag on the tracks this caregiver can see, sorted.
    public static function emotionVocabulary(?string $caregiverId)
    {
        return static::visibleTo($caregiverId)
            ->pluck('tags')
            ->flatMap(fn ($t) => array_map('trim', explode(',', (string) $t)))
            ->filter()
            ->unique()
            ->sort()
            ->values();
    }

    // Emotion tags as a clean list of trimmed strings.
    public function tagsArray(): array
    {
        return array_values(array_filter(
            array_map('trim', explode(',', $this->tags ?? ''))
        ));
    }

    // What the picker filters by: the genre (if known) and the emotion tags.
    public function filterTags(): array
    {
        $tags = $this->tagsArray();
        if ($this->genre && !in_array(strtolower($this->genre), array_map('strtolower', $tags), true)) {
            array_unshift($tags, $this->genre);
        }
        return $tags;
    }
}
