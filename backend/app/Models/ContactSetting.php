<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Collection;

/* One caregiver's settings for another member (favorite, blocked, muted,
   chat background). No row means all the defaults. */
class ContactSetting extends Model
{
    use HasUuids;

    protected $table = 'contact_settings';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'caregiver_id',
        'contact_id',
        'is_favorite',
        'is_blocked',
        'is_muted',
        'background_type',
        'background_value',
    ];

    protected $casts = [
        'is_favorite' => 'boolean',
        'is_blocked'  => 'boolean',
        'is_muted'    => 'boolean',
    ];

    protected $attributes = [
        'is_favorite'     => false,
        'is_blocked'      => false,
        'is_muted'        => false,
        'background_type' => 'none',
    ];

    // My settings for [contactId]; an unsaved row of defaults if I have none.
    public static function of(string $caregiverId, string $contactId): self
    {
        return static::where('caregiver_id', $caregiverId)
            ->where('contact_id', $contactId)
            ->first()
            ?? new static(['caregiver_id' => $caregiverId, 'contact_id' => $contactId]);
    }

    // My settings for each of [contactIds], keyed by contact id.
    public static function forContacts(string $caregiverId, iterable $contactIds): Collection
    {
        return static::where('caregiver_id', $caregiverId)
            ->whereIn('contact_id', collect($contactIds)->all())
            ->get()
            ->keyBy('contact_id');
    }

    // Either of the two has blocked the other.
    public static function blockedBetween(string $a, string $b): bool
    {
        return static::where('is_blocked', true)
            ->where(function ($q) use ($a, $b) {
                $q->where(fn ($q) => $q->where('caregiver_id', $a)->where('contact_id', $b))
                  ->orWhere(fn ($q) => $q->where('caregiver_id', $b)->where('contact_id', $a));
            })
            ->exists();
    }

    // Everyone this caregiver blocked or was blocked by.
    public static function blockedIdsFor(string $caregiverId): array
    {
        $iBlocked = static::where('caregiver_id', $caregiverId)
            ->where('is_blocked', true)->pluck('contact_id');
        $blockedMe = static::where('contact_id', $caregiverId)
            ->where('is_blocked', true)->pluck('caregiver_id');
        return $iBlocked->merge($blockedMe)->unique()->values()->all();
    }
}
