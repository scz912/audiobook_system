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
        'track_id', 'title', 'composer', 'file_path',
        'tags', 'tempo', 'duration_secs', 'status',
    ];

    protected $casts = [
        'duration_secs' => 'integer',
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

    // Tags as a clean list of trimmed strings.
    public function tagsArray(): array
    {
        return array_values(array_filter(
            array_map('trim', explode(',', $this->tags ?? ''))
        ));
    }
}
