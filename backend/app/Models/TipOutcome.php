<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/* One applied tip, waiting to see whether it helped. [baseline] holds the
   child's listening numbers when it was applied; a few sessions later
   TipLearner compares and fills in [result]. */
class TipOutcome extends Model
{
    use HasUuids;

    protected $table = 'tip_outcomes';
    protected $primaryKey = 'outcome_id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'child_id', 'arm', 'applied_at', 'baseline',
        'evaluated_at', 'result', 'change',
    ];

    protected $casts = [
        'applied_at'   => 'datetime',
        'evaluated_at' => 'datetime',
        'baseline'     => 'array',
        'change'       => 'float',
    ];

    public function uniqueIds(): array
    {
        return ['outcome_id'];
    }
}
