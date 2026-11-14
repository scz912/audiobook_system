<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/* How far one kind of tip ("arm") is trusted, for one child or for
   everyone (scope "global"). alpha and beta are the Beta belief:
   alpha grows when it's accepted or helps, beta when it's dismissed or
   doesn't. See TipLearner. */
class TipLearning extends Model
{
    public const GLOBAL = 'global';

    protected $table = 'tip_learning';

    protected $fillable = [
        'scope', 'arm', 'alpha', 'beta',
        'accepted', 'edited', 'dismissed', 'helped', 'not_helped',
    ];

    protected $casts = [
        'alpha'      => 'float',
        'beta'       => 'float',
        'accepted'   => 'integer',
        'edited'     => 'integer',
        'dismissed'  => 'integer',
        'helped'     => 'integer',
        'not_helped' => 'integer',
    ];

    protected $attributes = [
        'alpha'      => 1.0,
        'beta'       => 1.0,
        'accepted'   => 0,
        'edited'     => 0,
        'dismissed'  => 0,
        'helped'     => 0,
        'not_helped' => 0,
    ];
}
