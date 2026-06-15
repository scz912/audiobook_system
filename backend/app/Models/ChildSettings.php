<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ChildSettings extends Model
{
    use HasFactory;
    use HasUuids;

    protected $table = 'child_settings';
    protected $primaryKey = 'setting_id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'child_id',
        'narrator_voice',
        'reading_speed',
        'volume',
        'text_scale',
        'reduced_animations',
        'auto_play_next',
        'read_along',
    ];

    protected $casts = [
        'reading_speed'      => 'float',
        'volume'             => 'float',
        'text_scale'         => 'float',
        'reduced_animations' => 'boolean',
        'auto_play_next'     => 'boolean',
        'read_along'         => 'boolean',
    ];

    // Defaults so a brand-new row shows the right values.
    protected $attributes = [
        'narrator_voice'     => 'calm_female',
        'reading_speed'      => 1.00,
        'volume'             => 0.80,
        'text_scale'         => 1.00,
        'reduced_animations' => true,
        'auto_play_next'     => true,
        'read_along'         => true,
    ];

    public const ALLOWED_VOICES = [
        'calm_female',
        'gentle_female',
        'warm_male',
        'friendly_child',
        'soothing_elder',
    ];

    public function uniqueIds(): array
    {
        return ['setting_id'];
    }

    public function child(): BelongsTo
    {
        return $this->belongsTo(ChildProfile::class, 'child_id', 'child_id');
    }
}
