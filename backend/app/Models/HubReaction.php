<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

// One person's emoji reaction to a hub post (at most one each).
class HubReaction extends Model
{
    use HasUuids;

    protected $table = 'hub_reactions';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'post_id',
        'caregiver_id',
        'emoji',
    ];

    // The emoji people can react with. The heart is the like button instead.
    public const EMOJI = [
        "\u{1F44D}", // thumbs up
        "\u{1F602}", // laughing
        "\u{1F62E}", // surprised
        "\u{1F622}", // sad
        "\u{1F389}", // party
        "\u{1F64F}", // thank you
        "\u{1F970}", // loving
        "\u{1F44F}", // clapping
    ];
}
