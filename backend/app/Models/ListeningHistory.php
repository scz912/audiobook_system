<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ListeningHistory extends Model
{
    use HasFactory;
    use HasUuids;

    protected $table = 'listening_history';
    protected $primaryKey = 'history_id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'child_id',
        'audiobook_id',
        'duration_seconds',
        'last_position_seconds',
        'mood',
        'completed',
        'pause_count',
        'skip_count',
        'pages_total',
        'pages_reached',
        'back_count',
        'speed_used',
        'text_scale_used',
        'voice_used',
    ];

    protected $casts = [
        'duration_seconds'      => 'integer',
        'last_position_seconds' => 'integer',
        'completed'             => 'boolean',
        'pause_count'           => 'integer',
        'skip_count'            => 'integer',
        'pages_total'           => 'integer',
        'pages_reached'         => 'integer',
        'back_count'            => 'integer',
        'speed_used'            => 'float',
        'text_scale_used'       => 'float',
    ];

    public function uniqueIds(): array
    {
        return ['history_id'];
    }

    public function childProfile(): BelongsTo
    {
        return $this->belongsTo(ChildProfile::class, 'child_id', 'child_id');
    }

    public function audiobook(): BelongsTo
    {
        return $this->belongsTo(Audiobook::class, 'audiobook_id', 'audiobook_id');
    }
}
