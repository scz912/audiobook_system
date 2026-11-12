<?php

namespace Database\Seeders;

use App\Models\MusicTrack;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

class MusicTrackSeeder extends Seeder
{
    /**
     * Tags are comma-separated mood descriptors used for AI auto-selection and
     * caregiver filtering. Each tag spans at least 2 tracks so it is meaningful
     * as a filter. Tags are title-cased for consistent display.
     *
     * Tags and lengths match the audio files in storage/app/public/bgm
     * (checked by listening, Nov 2026: "December Rain" is a cheerful ukulele
     * piece and "Happy Happy Kids Music" a calm piano melody, despite their
     * names). Live databases get the same corrections from the
     * 2026_11_12_000002 migration.
     *
     * Tag coverage across the 6 tracks:
     *   Happy       → 1, 2
     *   Upbeat      → 1
     *   Energetic   → 1
     *   Playful     → 1, 2, 6
     *   Calm        → 3, 5
     *   Gentle      → 2, 5, 6
     *   Soothing    → 3, 5
     *   Peaceful    → 3, 5
     *   Relaxing    → 3, 5
     *   Mysterious  → 4  (distinctive mood anchor)
     *   Adventurous → 4, 6
     *   Imaginative → 4, 6
     *   Curious     → 4, 6
     *   Whimsical   → 2, 6
     */
    public function run(): void
    {
        $tracks = [
            [
                'title'        => 'Happy Kids Background Music',
                'composer'     => 'Bombinsound',
                'file_path'    => 'storage/bgm/bombinsound-happy-kids-background-music-499554.mp3',
                'tags'         => 'Happy,Upbeat,Energetic,Playful',
                'tempo'        => 'upbeat',
                'duration_secs'=> 157,
            ],
            [
                'title'        => 'December Rain',
                'composer'     => 'Ceeprolific',
                'file_path'    => 'storage/bgm/ceeprolific-december-rain-274814.mp3',
                'tags'         => 'Happy,Playful,Gentle,Whimsical',
                'tempo'        => 'moderate',
                'duration_secs'=> 79,
            ],
            [
                'title'        => 'Relaxing Sleep Music with Soft Ambient Rain',
                'composer'     => 'Desifreemusic',
                'file_path'    => 'storage/bgm/desifreemusic-relaxing-sleep-music-with-soft-ambient-rain-369762.mp3',
                'tags'         => 'Calm,Soothing,Peaceful,Relaxing',
                'tempo'        => 'slow',
                'duration_secs'=> 151,
            ],
            [
                'title'        => 'Mystery of Time',
                'composer'     => 'Emmraan',
                'file_path'    => 'storage/bgm/emmraan-mystery-of-time-213387.mp3',
                'tags'         => 'Mysterious,Adventurous,Imaginative,Curious',
                'tempo'        => 'moderate',
                'duration_secs'=> 137,
            ],
            [
                'title'        => 'Happy Happy Kids Music',
                'composer'     => 'Sigma Music Art',
                'file_path'    => 'storage/bgm/sigmamusicart-happy-happy-kids-music-537737.mp3',
                'tags'         => 'Calm,Gentle,Peaceful,Relaxing,Soothing',
                'tempo'        => 'moderate',
                'duration_secs'=> 52,
            ],
            [
                'title'        => 'Once Upon a Time',
                'composer'     => 'Sonican',
                'file_path'    => 'storage/bgm/sonican-once-upon-a-time-children-loop-384715.mp3',
                'tags'         => 'Gentle,Playful,Whimsical,Imaginative,Adventurous,Curious',
                'tempo'        => 'moderate',
                'duration_secs'=> 110,
            ],
        ];

        foreach ($tracks as $data) {
            MusicTrack::firstOrCreate(
                ['title' => $data['title'], 'composer' => $data['composer']],
                array_merge($data, ['track_id' => (string) Str::uuid()])
            );
        }
    }
}
