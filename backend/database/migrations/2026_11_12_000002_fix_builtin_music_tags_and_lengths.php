<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/* Corrects the built-in background tracks to match their audio files.

   Checked by listening (Nov 2026): "December Rain" is a cheerful ukulele
   piece, not calm, and "Happy Happy Kids Music" is a calm piano melody, not
   upbeat - so their emotion tags were swapped in spirit, and the story
   auto-match could put cheerful music under a calm bedtime story. The
   stored lengths were also those of longer versions than the files we ship
   (the picker showed 4:34 for a 2:31 track).

   Only built-in rows (no caregiver) are touched, matched by their file. */
return new class extends Migration
{
    private const FIXES = [
        'storage/bgm/ceeprolific-december-rain-274814.mp3' => [
            'new' => ['tags' => 'Happy,Playful,Gentle,Whimsical', 'tempo' => 'moderate', 'duration_secs' => 79],
            'old' => ['tags' => 'Calm,Gentle,Soothing,Peaceful', 'tempo' => 'slow', 'duration_secs' => 303],
        ],
        'storage/bgm/sigmamusicart-happy-happy-kids-music-537737.mp3' => [
            'new' => ['tags' => 'Calm,Gentle,Peaceful,Relaxing,Soothing', 'tempo' => 'moderate', 'duration_secs' => 52],
            'old' => ['tags' => 'Happy,Upbeat,Energetic,Playful,Whimsical', 'tempo' => 'upbeat', 'duration_secs' => 219],
        ],
        'storage/bgm/desifreemusic-relaxing-sleep-music-with-soft-ambient-rain-369762.mp3' => [
            'new' => ['duration_secs' => 151],
            'old' => ['duration_secs' => 274],
        ],
        'storage/bgm/emmraan-mystery-of-time-213387.mp3' => [
            'new' => ['duration_secs' => 137],
            'old' => ['duration_secs' => 105],
        ],
        'storage/bgm/sonican-once-upon-a-time-children-loop-384715.mp3' => [
            'new' => ['duration_secs' => 110],
            'old' => ['duration_secs' => 220],
        ],
    ];

    public function up(): void
    {
        $this->apply('new');
    }

    public function down(): void
    {
        $this->apply('old');
    }

    private function apply(string $which): void
    {
        foreach (self::FIXES as $file => $values) {
            DB::table('music_tracks')
                ->whereNull('caregiver_id')
                ->where('file_path', $file)
                ->update($values[$which]);
        }
    }
};
