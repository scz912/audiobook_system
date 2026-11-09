<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class CaregiverSettings extends Model
{
    use HasFactory;
    use HasUuids;

    protected $table = 'caregiver_settings';
    protected $primaryKey = 'setting_id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'caregiver_id',
        'narrator_voice',
        'reading_speed',
        'volume',
        'reduced_animations',
        'auto_play_next',
        'read_along',
    ];

    protected $casts = [
        'reading_speed'      => 'float',
        'volume'             => 'float',
        'reduced_animations' => 'boolean',
        'auto_play_next'     => 'boolean',
        'read_along'         => 'boolean',
    ];

    // Two voices to choose from: one female, one male.
    public const ALLOWED_VOICES = [
        'calm_female',
        'warm_male',
    ];

    public function uniqueIds(): array
    {
        return ['setting_id'];
    }

    public function caregiver(): BelongsTo
    {
        return $this->belongsTo(Caregiver::class, 'caregiver_id', 'caregiver_id');
    }
}
