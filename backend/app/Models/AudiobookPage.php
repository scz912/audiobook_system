<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AudiobookPage extends Model
{
    use HasFactory;
    use HasUuids;

    protected $table = 'audiobook_pages';
    protected $primaryKey = 'page_id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'audiobook_id',
        'page_number',
        'text',
        'choices',
        'is_split',
        'branch_index',
        'image_prompt',
        'image',
        'audio_start_ms',
    ];

    protected $casts = [
        'page_number'    => 'integer',
        'audio_start_ms' => 'integer',
        'choices'        => 'array',
        'is_split'       => 'boolean',
        'branch_index'   => 'integer',
    ];

    // The token a placeholder response page uses for the child's answer.
    public const CHOICE_TOKEN = '{choice}';

    public function uniqueIds(): array
    {
        return ['page_id'];
    }

    public function audiobook(): BelongsTo
    {
        return $this->belongsTo(Audiobook::class, 'audiobook_id', 'audiobook_id');
    }
}
