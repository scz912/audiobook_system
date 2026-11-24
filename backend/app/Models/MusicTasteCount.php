<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/* How many YouTube / YouTube Music plays of one genre a child had on one
   day. Sent by the app (MusicTasteService); song names never reach here. */
class MusicTasteCount extends Model
{
    protected $table = 'music_taste_counts';

    protected $fillable = ['child_id', 'day', 'genre', 'plays'];

    protected $casts = [
        'day'   => 'date:Y-m-d',
        'plays' => 'integer',
    ];
}
