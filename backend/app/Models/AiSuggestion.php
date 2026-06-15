<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/* The latest saved Gemini tips for one child. The `items` JSON holds
   each tip and its status; the caregiver accepts, edits, or dismisses
   them one by one. */
class AiSuggestion extends Model
{
    use HasFactory;
    use HasUuids;

    protected $table = 'ai_suggestions';
    protected $primaryKey = 'suggestion_id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'child_id',
        'source_stats',
        'items',
        'confidence',
        'is_stale',
        'generated_at',
    ];

    protected $casts = [
        'source_stats' => 'array',
        'items'        => 'array',
        'is_stale'     => 'boolean',
        'generated_at' => 'datetime',
    ];

    public function uniqueIds(): array
    {
        return ['suggestion_id'];
    }

    public function child(): BelongsTo
    {
        return $this->belongsTo(ChildProfile::class, 'child_id', 'child_id');
    }
}
