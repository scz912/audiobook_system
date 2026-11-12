<?php

namespace App\Services;

use Illuminate\Http\Client\Pool;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class GeminiService
{
    private string $key;
    private string $textModel;
    private string $imageModel;
    private string $base = 'https://generativelanguage.googleapis.com/v1beta/models';

    // Why the last image call failed (null = it worked).
    private ?string $lastImageError = null;

    public function __construct()
    {
        $this->key = (string) config('services.gemini.key');
        $this->textModel = (string) config('services.gemini.text_model');
        $this->imageModel = (string) config('services.gemini.image_model');
    }

    public function isConfigured(): bool
    {
        return $this->key !== '';
    }

    // Why the last image call failed (null = it worked).
    public function imageError(): ?string
    {
        return $this->lastImageError;
    }

    /* Make a picture with Gemini and save it. Returns the path like
       "storage/uploads/covers/<uuid>.jpg", or null if it failed.
       Check imageError() for the reason. */
    public function downloadImage(string $prompt): ?string
    {
        $this->lastImageError = null;
        Log::info('[Gemini] downloadImage called', [
            'prompt_length' => strlen($prompt),
        ]);
        $result = $this->generateWithGemini($this->styledPrompt($prompt));
        Log::info('[Gemini] downloadImage finished', [
            'success'    => $result !== null,
            'path'       => $result,
            'last_error' => $this->lastImageError,
        ]);
        return $result;
    }

    /* Make several pictures at once (all requests fire together). Returns a
       path (or null) per prompt in the same order. On a paid key this is far
       faster than one at a time. 4 images finish in ~one image's time. */
    public function downloadImages(array $prompts): array
    {
        if (empty($prompts)) {
            return [];
        }
        Log::info('[Gemini] downloadImages called', ['count' => count($prompts)]);

        $responses = Http::pool(function (Pool $pool) use ($prompts) {
            $requests = [];
            foreach ($prompts as $i => $prompt) {
                $requests[] = $pool->as((string) $i)->timeout(120)->post(
                    "{$this->base}/{$this->imageModel}:generateContent?key={$this->key}",
                    [
                        'contents' => [
                            ['parts' => [['text' => $this->styledPrompt((string) $prompt)]]],
                        ],
                        'generationConfig' => [
                            'responseModalities' => ['IMAGE'],
                        ],
                    ]
                );
            }
            return $requests;
        });

        $out = [];
        foreach (array_keys($prompts) as $n => $key) {
            $out[$key] = $this->saveImageFromResponse($responses[(string) $n] ?? null);
        }
        Log::info('[Gemini] downloadImages finished', [
            'count'     => count($prompts),
            'succeeded' => count(array_filter($out, fn ($p) => $p !== null)),
        ]);
        return $out;
    }

    /* Pull the image out of a Gemini response, shrink it, and save it.
       Returns the public path, or null on any failure. */
    private function saveImageFromResponse($response): ?string
    {
        if (!$response instanceof Response) {
            return null;
        }
        if (!$response->successful()) {
            $this->lastImageError = $this->imageErrorMessage($response->status(), $response->json());
            return null;
        }
        $parts = data_get($response->json(), 'candidates.0.content.parts', []);
        foreach ($parts as $part) {
            $data = $part['inlineData']['data'] ?? $part['inline_data']['data'] ?? null;
            if ($data) {
                $binary = base64_decode($data, true);
                if ($binary === false) {
                    continue;
                }
                [$saveBytes, $ext] = $this->shrinkForWeb($binary);
                $path = 'uploads/covers/' . Str::uuid() . '.' . $ext;
                Storage::disk('public')->put($path, $saveBytes);
                return 'storage/' . $path;
            }
        }
        return null;
    }

    /* Make a voice clip from text using Gemini TTS. Cached by text + voice
       so we don't re-make the same one. Returns "storage/tts/<hash>.wav"
       or null on failure. */
    public function generateSpeech(string $text, string $voice = 'Kore'): ?string
    {
        $text = trim($text);
        if ($text === '') {
            return null;
        }

        Log::info('[Gemini] generateSpeech called', [
            'voice'       => $voice,
            'text_length' => strlen($text),
        ]);

        $path = 'tts/' . sha1($voice . '|' . $text) . '.wav';
        if (Storage::disk('public')->exists($path)) {
            Log::info('[Gemini] generateSpeech cache hit', ['path' => $path]);
            return 'storage/' . $path;
        }
        Log::info('[Gemini] generateSpeech cache miss. Calling Gemini TTS', [
            'voice' => $voice,
        ]);

        try {
            $model = 'gemini-2.5-flash-preview-tts';
            $response = Http::timeout(60)->post(
                "{$this->base}/{$model}:generateContent?key={$this->key}",
                [
                    'contents' => [
                        ['parts' => [['text' => $text]]],
                    ],
                    'generationConfig' => [
                        'responseModalities' => ['AUDIO'],
                        'speechConfig' => [
                            'voiceConfig' => [
                                'prebuiltVoiceConfig' => ['voiceName' => $voice],
                            ],
                        ],
                    ],
                ]
            );

            if (!$response->successful()) {
                Log::warning('[Gemini] TTS HTTP error', [
                    'status' => $response->status(),
                    'body'   => mb_substr($response->body(), 0, 300),
                ]);
                return null;
            }

            $b64 = data_get($response->json(), 'candidates.0.content.parts.0.inlineData.data')
                ?? data_get($response->json(), 'candidates.0.content.parts.0.inline_data.data');
            if (!$b64) {
                return null;
            }

            $pcm = base64_decode($b64, true);
            if ($pcm === false) {
                return null;
            }

            // Gemini gives us raw PCM audio. Wrap it in a WAV header so the
            // app can play it.
            Storage::disk('public')->put($path, $this->pcmToWav($pcm, 24000, 1, 16));
            Log::info('[Gemini] generateSpeech success', [
                'path'  => $path,
                'bytes' => strlen($pcm),
            ]);
            return 'storage/' . $path;
        } catch (\Throwable $e) {
            Log::warning('[Gemini] TTS exception', ['error' => $e->getMessage()]);
            return null;
        }
    }

    // Add a 44-byte WAV header to raw PCM bytes.
    private function pcmToWav(string $pcm, int $sampleRate, int $channels, int $bits): string
    {
        $byteRate   = $sampleRate * $channels * intdiv($bits, 8);
        $blockAlign = $channels * intdiv($bits, 8);
        $dataLen    = strlen($pcm);

        return 'RIFF' . pack('V', 36 + $dataLen) . 'WAVE'
            . 'fmt ' . pack('V', 16) . pack('v', 1) . pack('v', $channels)
            . pack('V', $sampleRate) . pack('V', $byteRate)
            . pack('v', $blockAlign) . pack('v', $bits)
            . 'data' . pack('V', $dataLen) . $pcm;
    }

    /* Ask Gemini for setting tweaks based on the child's listening stats.
       Each item has setting_key, suggested_value, and reason. Returns []
       on error. The caller falls back to the cached row. */
    public function analyseListening(array $stats): array
    {
        Log::info('[Gemini] analyseListening called', [
            'sessions_count' => $stats['sessions_count'] ?? null,
            'pause_rate'     => $stats['pause_rate'] ?? null,
            'skip_rate'      => $stats['skip_rate'] ?? null,
        ]);
        $payload = json_encode($stats, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
        $prompt = <<<PROMPT
You are advising a caregiver on how to better tune an audiobook reader app for
their autistic child. Below are anonymised, aggregated stats from the child's
recent listening sessions. Suggest sensory-friendly adjustments to the child's
in-app settings.

STATS (JSON):
{$payload}

Rules:
- Only suggest changes to known settings. Allowed setting_key values are
  exactly: "reading_speed", "narrator_voice", "volume", "text_scale",
  "auto_play_next", "read_along".
- For reading_speed: a number between 0.5 and 2.0 (step 0.05).
- For narrator_voice: "calm_female" or "warm_male".
- For volume: a number between 0.0 and 1.0 (step 0.05).
- For text_scale: a number between 0.7 and 2.0 (step 0.05).
- For auto_play_next, read_along: true or false.
- Each item's "reason" must be ONE very short sentence of at most 10 words,
  in simple everyday English: the reader may be an autistic teenager. No
  numbers, no clinical claims, no jargon (e.g. "You pause a lot, so slower
  may help.").
- Each item's "reason_ms" is the same sentence in simple Bahasa Melayu
  (e.g. "Anda kerap berhenti, jadi lebih perlahan mungkin membantu.").
- Do NOT suggest changes that match the current value already.
- At most 3 suggestions. Skip suggestions you are not confident about.

Return ONLY JSON with key "items".
PROMPT;

        try {
            $response = Http::timeout(45)->post(
                "{$this->base}/{$this->textModel}:generateContent?key={$this->key}",
                [
                    'contents' => [
                        ['parts' => [['text' => $prompt]]],
                    ],
                    'generationConfig' => [
                        'temperature'      => 0.4,
                        'responseMimeType' => 'application/json',
                        'responseSchema'   => [
                            'type'       => 'OBJECT',
                            'properties' => [
                                'items' => [
                                    'type'  => 'ARRAY',
                                    'items' => [
                                        'type'       => 'OBJECT',
                                        'properties' => [
                                            'setting_key'     => ['type' => 'STRING'],
                                            /* String here so Gemini can send numbers,
                                               booleans, or enums. We convert later. */
                                            'suggested_value' => ['type' => 'STRING'],
                                            'reason'          => ['type' => 'STRING'],
                                            'reason_ms'       => ['type' => 'STRING'],
                                        ],
                                        'required' => ['setting_key', 'suggested_value', 'reason', 'reason_ms'],
                                    ],
                                ],
                            ],
                            'required' => ['items'],
                        ],
                    ],
                ]
            );

            if (!$response->successful()) {
                Log::warning('[Gemini] analyseListening HTTP error', [
                    'status' => $response->status(),
                    'body'   => mb_substr($response->body(), 0, 300),
                ]);
                return [];
            }

            $text = data_get($response->json(), 'candidates.0.content.parts.0.text');
            if (!$text) {
                Log::warning('[Gemini] analyseListening empty response');
                return [];
            }
            $parsed = json_decode($text, true);
            $items = is_array($parsed) ? ($parsed['items'] ?? []) : [];

            // Clean up to the simple shape callers expect.
            $clean = [];
            foreach ($items as $item) {
                if (!is_array($item)) {
                    continue;
                }
                $key = (string) ($item['setting_key'] ?? '');
                $raw = $item['suggested_value'] ?? null;
                $reason = trim((string) ($item['reason'] ?? ''));
                if ($key === '' || $raw === null || $reason === '') {
                    continue;
                }
                $reasonMs = trim((string) ($item['reason_ms'] ?? ''));
                $clean[] = [
                    'setting_key'     => $key,
                    'suggested_value' => $raw,
                    'reason'          => $reason,
                    // Malay, so the tip reads in the app's language.
                    'reason_ms'       => $reasonMs !== '' ? $reasonMs : $reason,
                ];
            }
            Log::info('[Gemini] analyseListening success', [
                'items_returned' => count($items),
                'items_kept'     => count($clean),
            ]);
            return $clean;
        } catch (\Throwable $e) {
            Log::warning('[Gemini] analyseListening exception', ['error' => $e->getMessage()]);
            return [];
        }
    }

    /* The genres a track can be given (the picker's genre filter chips).
       Pairs that even people file either way are one genre: tested on 32
       labelled clips (Nov 2026), orchestral pieces split between Classical
       and Cinematic, soft piano pieces between Ambient and Lullaby, and solo
       traditional instruments between Folk and World. */
    public const MUSIC_GENRES = [
        'Classical & Cinematic', 'Nature', 'Pop', 'Jazz', 'Ambient & Lullaby',
        'Acoustic', 'Electronic', 'Folk & World',
    ];

    // Single or older genre names, mapped to the genre that now covers them.
    public const GENRE_ALIASES = [
        'classical' => 'Classical & Cinematic',
        'cinematic' => 'Classical & Cinematic',
        'ambient'   => 'Ambient & Lullaby',
        'lullaby'   => 'Ambient & Lullaby',
        'folk'      => 'Folk & World',
        'world'     => 'Folk & World',
    ];

    // The app's genre for [name] (a current genre or an older name), or null.
    public static function canonicalGenre(?string $name): ?string
    {
        $name = trim((string) $name);
        foreach (self::MUSIC_GENRES as $g) {
            if (strcasecmp($g, $name) === 0) {
                return $g;
            }
        }
        return self::GENRE_ALIASES[strtolower($name)] ?? null;
    }

    /* Let Gemini listen to a music file once and tag it. Returns
       ['genre' => 'Jazz', 'tags' => [...emotions], 'tempo' =>
       'slow|moderate|upbeat', 'summary' => '...', 'sensory_notes' => '...'],
       or null if the AI call failed.
       $vocabulary is the emotion tag list already used in the library, so
       new tracks reuse the same words (the picker filters and the story
       auto-match both rely on them). $rhythm is what AudioRhythmAnalyzer
       measured from the audio, if it could; the AI weighs it alongside what
       it hears. */
    public function analyseMusic(string $audioBytes, string $mimeType, string $title, array $vocabulary, ?array $rhythm = null): ?array
    {
        Log::info('[Gemini] analyseMusic called', [
            'title'  => $title,
            'bytes'  => strlen($audioBytes),
            'mime'   => $mimeType,
            'rhythm' => $rhythm !== null,
        ]);
        try {
            $response = Http::timeout(120)->post(
                $this->musicUrl(),
                $this->musicRequest($audioBytes, $mimeType, $title, $vocabulary, $rhythm),
            );
            return $this->readMusicAnswer($response, $vocabulary);
        } catch (\Throwable $e) {
            Log::warning('[Gemini] analyseMusic exception', ['error' => $e->getMessage()]);
            return null;
        }
    }

    /* Like analyseMusic, but Gemini listens twice (at the same time, so it
       takes no longer) and the genre is kept only when both listens agree.
       Tested on 32 labelled clips, a genre it gave differently between two
       listens was nearly always a wrong one, so an unsure genre is left
       blank (null) instead of shown. Emotions both listens gave come first.
       Adds 'genre_votes' => [first, second] to the result. */
    public function analyseMusicTwice(string $audioBytes, string $mimeType, string $title, array $vocabulary, ?array $rhythm = null): ?array
    {
        Log::info('[Gemini] analyseMusicTwice called', [
            'title'  => $title,
            'bytes'  => strlen($audioBytes),
            'rhythm' => $rhythm !== null,
        ]);
        $url = $this->musicUrl();
        $body = $this->musicRequest($audioBytes, $mimeType, $title, $vocabulary, $rhythm);
        try {
            $responses = Http::pool(fn (Pool $pool) => [
                $pool->timeout(120)->post($url, $body),
                $pool->timeout(120)->post($url, $body),
            ]);
        } catch (\Throwable $e) {
            Log::warning('[Gemini] analyseMusicTwice exception', ['error' => $e->getMessage()]);
            return null;
        }

        $answers = [];
        foreach ($responses as $response) {
            if ($response instanceof Response) {
                $answer = $this->readMusicAnswer($response, $vocabulary);
                if ($answer !== null) {
                    $answers[] = $answer;
                }
            } else {
                Log::warning('[Gemini] analyseMusicTwice listen failed', [
                    'error' => $response instanceof \Throwable ? $response->getMessage() : 'unknown',
                ]);
            }
        }
        if (!$answers) {
            return null;
        }
        $result = self::agree($answers);
        Log::info('[Gemini] analyseMusicTwice result', $result);
        return $result;
    }

    /* Combine two listens' answers (see analyseMusicTwice). With only one
       answer (the other call failed) it is used as it is - a failed call is
       not a disagreement. */
    public static function agree(array $answers): array
    {
        $a = $answers[0];
        $b = $answers[1] ?? null;
        if ($b === null) {
            return $a + ['genre_votes' => [$a['genre']]];
        }

        // Emotions both listens heard first, then topped up to at least 3.
        $inB = array_map('strtolower', $b['tags']);
        $tags = array_values(array_filter($a['tags'], fn ($t) => in_array(strtolower($t), $inB, true)));
        foreach (array_merge($a['tags'], $b['tags']) as $t) {
            if (count($tags) >= 3) {
                break;
            }
            if (!in_array(strtolower($t), array_map('strtolower', $tags), true)) {
                $tags[] = $t;
            }
        }

        return [
            'genre'         => $a['genre'] !== null && $a['genre'] === $b['genre'] ? $a['genre'] : null,
            'tags'          => array_slice($tags, 0, 6),
            'tempo'         => $a['tempo'] ?? $b['tempo'],
            'summary'       => $a['summary'] !== '' ? $a['summary'] : $b['summary'],
            // A caution either listen heard is kept: a false alarm is better
            // than a missed one.
            'sensory_notes' => $a['sensory_notes'] !== '' ? $a['sensory_notes'] : $b['sensory_notes'],
            'genre_votes'   => [$a['genre'], $b['genre']],
        ];
    }

    private function musicUrl(): string
    {
        return "{$this->base}/{$this->textModel}:generateContent?key={$this->key}";
    }

    // The request body for one listen.
    private function musicRequest(string $audioBytes, string $mimeType, string $title, array $vocabulary, ?array $rhythm): array
    {
        $tagList = implode(', ', $vocabulary);
        $genreList = implode(', ', self::MUSIC_GENRES);
        $measured = $rhythm !== null
            ? "Measurements taken from the audio itself (trust these numbers over a guess,\n"
              . "but use your ears to judge what they mean):\n"
              . AudioRhythmAnalyzer::describe($rhythm)
            : 'No measurements are available for this track; judge from listening alone.';
        $prompt = <<<PROMPT
You are a music therapist who curates background music for an audiobook app made
for autistic children and teenagers (under 18). A caregiver has uploaded the
attached audio, titled "{$title}". It will play quietly underneath a narrator
reading a story aloud.

Listen to the WHOLE track before answering, then analyse:
1. Mood and character: what feeling does it create (calm, playful, mysterious...)?
2. Flow over time: how it opens, whether it builds, peaks, or changes section,
   and how it ends. Note whether the energy stays steady or shifts.
3. Tempo and rhythm: overall speed and how strong or busy the beat is.
4. Instruments and texture: what you hear, and whether it is sparse or dense.
5. Sensory risks for autistic listeners: sudden loud moments, sharp or
   piercing high sounds, heavy bass or drops, harsh distortion, abrupt stops,
   alarms or sirens, crowd noise, or singing/lyrics that would compete with
   the narrator's voice.

{$measured}

Use the rhythm to read the emotion, together with harmony and sound:
- A steady, quick pulse with busy notes usually feels happy, playful or
  energetic; a slow or absent pulse with sparse notes feels calm, peaceful or
  sleepy; an uneven pulse, dark tone or minor harmony can feel mysterious or
  curious; big loudness swings feel dramatic or adventurous.
- A steady pulse is not always lively: gentle piano arpeggios can be as
  regular as drums. Decide how fast it FEELS by listening.

Then return:
- "genre": the ONE genre that best fits, exactly one of: {$genreList}.
  Classical & Cinematic = classical repertoire or classical-style piano,
  strings or orchestra, and film, trailer or game scores.
  Nature = mostly natural sounds (rain, thunder, birds, insects, sea, wind,
  streams), with or without soft music; a plain recording of nature with no
  music at all is still Nature.
  Ambient & Lullaby = slow pads or textures without a clear tune, and soft,
  rocking songs or melodies made for sleep.
  Folk & World = traditional and folk songs or tunes from any country or
  culture, including solo traditional instruments.
  Jazz = jazz, swing, ragtime, blues and early dance-band music (fox-trots,
  1920s orchestras), old recordings included.
  Acoustic = modern songs or instrumentals led by acoustic guitar, ukulele or
  piano that are not folk. Pop = modern catchy songs or bright instrumentals
  with a band or a beat. Electronic = music made mainly from synthesizers and
  electronic beats.
- "tags": 3 to 6 emotion tags describing the track as a whole, in Title
  Case, one word each. Strongly prefer words from this existing list:
  {$tagList}
  Use a new word only if none of these fit, and add at most one new word.
  Do not tag an emotion that only appears briefly; tag what the listener
  feels for most of the track. Never use a genre name as a tag.
- "tempo": exactly one of "slow", "moderate", "upbeat" - how fast it feels.
- "summary": one short, plain sentence a caregiver can read at a glance,
  describing the music and how it flows (e.g. "Soft piano over gentle rain
  that stays quiet and steady from start to finish.").
- "sensory_notes": one short, plain sentence naming any sensory risk from
  step 5 and roughly when it happens (e.g. "Has a sudden loud drum hit around
  1:30."). Check any measured sudden loud jumps by listening; mention the
  ones that would startle. Use an empty string if there are none. No
  clinical claims.

Recordings of nature (rain, birds, the sea...) are welcome background sound:
tag them as Nature with emotion tags like any other track. Only if the audio
is neither music nor nature (speech, silence, machine or crowd noise), return
an empty "tags" list, "tempo" "slow", "genre" "Ambient & Lullaby", and explain
in "sensory_notes" that it is not music.

Return ONLY JSON.
PROMPT;

        return [
            'contents' => [
                ['parts' => [
                    ['inline_data' => ['mime_type' => $mimeType, 'data' => base64_encode($audioBytes)]],
                    ['text' => $prompt],
                ]],
            ],
            'generationConfig' => [
                'temperature'      => 0.3,
                'responseMimeType' => 'application/json',
                'responseSchema'   => [
                    'type'       => 'OBJECT',
                    'properties' => [
                        'genre'         => ['type' => 'STRING', 'enum' => self::MUSIC_GENRES],
                        'tags'          => ['type' => 'ARRAY', 'items' => ['type' => 'STRING']],
                        'tempo'         => ['type' => 'STRING', 'enum' => ['slow', 'moderate', 'upbeat']],
                        'summary'       => ['type' => 'STRING'],
                        'sensory_notes' => ['type' => 'STRING'],
                    ],
                    'required' => ['genre', 'tags', 'tempo', 'summary', 'sensory_notes'],
                ],
            ],
        ];
    }

    // One listen's answer, cleaned; null if the call failed or was unreadable.
    private function readMusicAnswer(Response $response, array $vocabulary): ?array
    {
        if (!$response->successful()) {
            Log::warning('[Gemini] music HTTP error', [
                'status' => $response->status(),
                'body'   => mb_substr($response->body(), 0, 300),
            ]);
            return null;
        }

        $text = data_get($response->json(), 'candidates.0.content.parts.0.text');
        $parsed = $text ? json_decode($text, true) : null;
        if (!is_array($parsed)) {
            Log::warning('[Gemini] music answer unreadable');
            return null;
        }

        /* Clean the tags: one word, Title Case, no commas (tags are stored
           comma-separated), no repeats, at most 6. Match the existing
           spelling when the word is already in the library. */
        $known = [];
        foreach ($vocabulary as $v) {
            $known[strtolower($v)] = $v;
        }
        $tags = [];
        // Each new word becomes a filter chip for everyone, so only the
        // first word the library doesn't have yet is kept (as the prompt asks).
        $newWords = 0;
        foreach ((array) ($parsed['tags'] ?? []) as $tag) {
            $word = trim(str_replace(',', ' ', (string) $tag));
            // The genre has its own field; keep genre names out of the emotions.
            if ($word === '' || mb_strlen($word) > 20 || self::canonicalGenre($word) !== null) {
                continue;
            }
            $isNew = !isset($known[strtolower($word)]);
            if ($isNew && $vocabulary && $newWords >= 1) {
                continue;
            }
            $word = $known[strtolower($word)] ?? Str::title($word);
            if (!in_array($word, $tags, true)) {
                $tags[] = $word;
                $newWords += $isNew ? 1 : 0;
            }
        }

        $tempo = (string) ($parsed['tempo'] ?? '');
        return [
            'genre'         => self::canonicalGenre($parsed['genre'] ?? null),
            'tags'          => array_slice($tags, 0, 6),
            'tempo'         => in_array($tempo, ['slow', 'moderate', 'upbeat'], true) ? $tempo : null,
            'summary'       => mb_substr(trim((string) ($parsed['summary'] ?? '')), 0, 500),
            'sensory_notes' => mb_substr(trim((string) ($parsed['sensory_notes'] ?? '')), 0, 500),
        ];
    }

    // Add a soft, calm illustration style to the prompt.
    private function styledPrompt(string $prompt): string
    {
        return 'A soft, calming, child-friendly storybook illustration. '
            . 'Gentle pastel colours, simple rounded shapes, no text, nothing scary. '
            . 'Scene: ' . $prompt;
    }

    // Who the story is for. The age is optional; caregivers no longer pick one.
    private function audience(?string $ageGroup): string
    {
        return $ageGroup ? "autistic children aged {$ageGroup}" : 'young autistic children';
    }

    /* How much text goes on each page, from the caregiver's difficulty:
       Easy = 1 sentence, Medium = 2, Hard = 3 or more. */
    private function sentencesPerPage(?string $difficulty): string
    {
        return match (strtolower((string) $difficulty)) {
            'medium' => 'exactly two short, simple sentences',
            'hard'   => 'three to five simple sentences (never fewer than three)',
            default  => 'exactly one short, simple sentence',
        };
    }

    // Make a paged, autism-friendly story.
    public function generateStory(string $topic, ?string $ageGroup, ?string $sourceText, ?int $pageCount = null, ?string $language = null, ?string $difficulty = null): array
    {
        Log::info('[Gemini] generateStory called', [
            'topic'      => $topic,
            'age_group'  => $ageGroup,
            'page_count' => $pageCount,
            'language'   => $language,
            'difficulty' => $difficulty,
            'model'      => $this->textModel,
        ]);
        $audience = $this->audience($ageGroup);
        $sentences = $this->sentencesPerPage($difficulty);
        $instruction = ($sourceText !== null && trim($sourceText) !== '')
            ? "Rewrite the following text into a calming, autism-friendly children's story.\n\nTEXT:\n" . trim($sourceText)
            : "Write a calming, autism-friendly children's story about: {$topic}";

        /* Use the caregiver's page count if given. Otherwise keep it small
           since each page is a separate image (~12s). */
        $lengthRule = ($pageCount !== null && $pageCount > 0)
            ? "Split the story into exactly {$pageCount} short pages, like a picture book."
            : 'Split the story into between 4 and 6 short pages, like a picture book - '
                . 'choose a sensible length for the topic.';

        /* Tell Gemini what language to write in. Image prompts stay English
           so the image model gets clear, simple words. */
        $code = strtolower($language ?? 'en');
        $languageRule = match ($code) {
            'ms' => "Write the story TEXT (the 'text' field for every page, and the 'title') in Bahasa Malaysia (standard Malay). Keep \"image_prompt\" in English. It goes to the image generator and must stay clear and literal.",
            default => 'Write the story in clear, simple English.',
        };

        $prompt = <<<PROMPT
You are an author creating gentle, sensory-friendly stories for {$audience}.
{$instruction}

Stay close to what the reader asked for: keep the characters, setting, and ideas
they described, and make the story actually about their request.

{$languageRule}

{$lengthRule}
For each page give:
- "text": {$sentences} for that page.
- "image_prompt": a clear description of a gentle illustration for THAT page's scene.

Rules:
- Count the sentences on every page. Each page's "text" must have {$sentences}.
- Keep a calm, warm, predictable tone. No scary, loud, or sudden events.
- Avoid idioms and sarcasm; be literal and clear.
- Each page's text should follow on naturally from the page before.
- Each "image_prompt" MUST be self-contained: restate the main character's
  name and appearance every time so every illustration looks consistent, and
  describe only what happens on that page.

Return ONLY JSON with keys: title (string) and pages (array of page objects).
PROMPT;

        $response = Http::timeout(60)->post(
            "{$this->base}/{$this->textModel}:generateContent?key={$this->key}",
            [
                'contents' => [
                    ['parts' => [['text' => $prompt]]],
                ],
                'generationConfig' => [
                    'temperature' => 0.8,
                    'responseMimeType' => 'application/json',
                    'responseSchema' => [
                        'type' => 'OBJECT',
                        'properties' => [
                            'title' => ['type' => 'STRING'],
                            'pages' => [
                                'type'  => 'ARRAY',
                                'items' => [
                                    'type'       => 'OBJECT',
                                    'properties' => [
                                        'text'         => ['type' => 'STRING'],
                                        'image_prompt' => ['type' => 'STRING'],
                                    ],
                                    'required' => ['text', 'image_prompt'],
                                ],
                            ],
                        ],
                        'required' => ['title', 'pages'],
                    ],
                ],
            ]
        );

        if ($response->status() === 429) {
            Log::warning('[Gemini] generateStory quota exceeded (429)', [
                'body' => $response->body(),
            ]);
            throw new \RuntimeException($this->quotaMessage($response->json()));
        }

        if (!$response->successful()) {
            Log::error('[Gemini] generateStory HTTP error', [
                'status' => $response->status(),
                'body'   => $response->body(),
            ]);
            throw new \RuntimeException('Gemini text generation failed (HTTP ' . $response->status() . ')');
        }

        $text = data_get($response->json(), 'candidates.0.content.parts.0.text');
        if (!$text) {
            throw new \RuntimeException('Gemini returned no content');
        }

        $parsed = json_decode($text, true);
        $title = trim((string) ($parsed['title'] ?? ($topic !== '' ? $topic : 'A Gentle Story')));

        // Clean up the pages list. Fall back to one page if needed.
        $pages = [];
        if (is_array($parsed) && !empty($parsed['pages']) && is_array($parsed['pages'])) {
            foreach ($parsed['pages'] as $page) {
                $pageText = trim((string) ($page['text'] ?? ''));
                if ($pageText === '') {
                    continue;
                }
                $pages[] = [
                    'text'         => $pageText,
                    'image_prompt' => trim((string) ($page['image_prompt'] ?? $pageText)),
                ];
            }
        }

        if (empty($pages)) {
            // No usable pages. Use the whole reply as one page.
            $body = (is_array($parsed) && !empty($parsed['story']))
                ? trim((string) $parsed['story'])
                : trim((string) $text);
            $pages[] = ['text' => $body, 'image_prompt' => $topic !== '' ? $topic : $title];
        }

        Log::info('[Gemini] generateStory success', [
            'pages' => count($pages),
            'title' => $title,
        ]);
        return [
            'title'        => $title,
            'content'      => implode("\n\n", array_column($pages, 'text')),
            'image_prompt' => $pages[0]['image_prompt'],
            'pages'        => $pages,
        ];
    }

    /* Lay out an interactive book before asking the AI to write it, so the
       structure is decided by us, not guessed by the model. Returns one
       entry per page number: 'story', 'interaction' (placeholder answer),
       'interaction_split', 'response' (uses {choice}) or 'split' (two
       versions). Rules:
       - at most floor(pages / 4) interactions,
       - never on page 1 or the last page, and never on a response page,
       - interactions are spread evenly, splits spread evenly among them. */
    public static function planInteractiveStory(int $pageCount, int $interactions, int $splits): array
    {
        $interactions = max(0, min($interactions, intdiv($pageCount, 4)));
        $splits = max(0, min($splits, $interactions));

        $plan = array_fill(1, $pageCount, 'story');
        for ($i = 0; $i < $interactions; $i++) {
            /* Even spacing. With at most pages/4 interactions the gap is
               always >= 2, so a response page never lands on an
               interaction, and the last one stays before the final page. */
            $at = (int) round(($i + 1) * $pageCount / ($interactions + 1));
            $isSplit = intdiv(($i + 1) * $splits, $interactions) > intdiv($i * $splits, $interactions);
            $plan[$at] = $isSplit ? 'interaction_split' : 'interaction';
            $plan[$at + 1] = $isSplit ? 'split' : 'response';
        }
        return $plan;
    }

    /* Write an interactive, autism-friendly story that follows
       planInteractiveStory(). Returns ['title', 'content', 'pages'] where
       each page is a ready-to-save row: page_number, text, image_prompt,
       choices (or null), is_split, branch_index (or null). Split pages come
       back as two rows with the same page_number. Throws on failure. */
    public function generateInteractiveStory(
        string $topic,
        ?string $ageGroup,
        ?string $sourceText,
        int $pageCount,
        int $interactions,
        int $splits,
        ?string $language = null,
        ?string $difficulty = null
    ): array {
        $plan = self::planInteractiveStory($pageCount, $interactions, $splits);
        Log::info('[Gemini] generateInteractiveStory called', [
            'topic' => $topic,
            'plan'  => $plan,
        ]);

        $audience = $this->audience($ageGroup);
        $sentences = $this->sentencesPerPage($difficulty);
        $token = \App\Models\AudiobookPage::CHOICE_TOKEN;
        $instruction = ($sourceText !== null && trim($sourceText) !== '')
            ? "Turn the following text into a calming, autism-friendly interactive children's story.\n\nTEXT:\n" . trim($sourceText)
            : "Write a calming, autism-friendly interactive children's story about: {$topic}";
        $languageRule = $this->languageRule($language)
            . " The token {$token} is code: always write it exactly like that, never translate it.";

        $planLines = [];
        foreach ($plan as $n => $kind) {
            $planLines[] = "Page {$n}: " . match ($kind) {
                'interaction'       => 'INTERACTION page (placeholder answer). Give 2 or 3 choices.',
                'response'          => 'PLACEHOLDER RESPONSE page for page ' . ($n - 1) . ". Its text must contain {$token} exactly once.",
                'interaction_split' => 'INTERACTION page (split). Give exactly 2 choices.',
                'split'             => 'SPLIT page. Write two versions in "branches": branches[0] follows choice 1 of page '
                    . ($n - 1) . ', branches[1] follows choice 2. Leave "text" and "image_prompt" empty.',
                default             => ($n > 1 && ($plan[$n - 1] ?? '') === 'split')
                    ? 'STORY page. It must follow on naturally from BOTH versions of page ' . ($n - 1) . '.'
                    : 'STORY page.',
            };
        }
        $planText = implode("\n", $planLines);

        $prompt = <<<PROMPT
You are an author creating gentle, sensory-friendly INTERACTIVE stories for
{$audience}.
{$instruction}

Stay close to what the reader asked for: keep the characters, setting, and ideas
they described, and make the story actually about their request.

{$languageRule}

HOW AN INTERACTIVE STORY WORKS
The story is read aloud one page at a time. On an INTERACTION page the narrator
asks the child a question and the story pauses until the child taps one of the
choices. What happens next depends on the answer:
- PLACEHOLDER RESPONSE: the next page is the same for everyone, but contains the
  exact token {$token}, which the app replaces with the choice the child tapped.
- SPLIT: the next page is written in two different versions, one per choice.
  Only the version for the chosen answer is read. The page after it is the same
  for everyone again, so the story always comes back together.

PAGE PLAN (follow it exactly; there are exactly {$pageCount} pages, in this order)
{$planText}

For each page return:
- "page_number": the page number from the plan.
- "text": {$sentences} (empty on SPLIT pages). On an INTERACTION page the
  question counts as one of these sentences.
- "image_prompt": a clear description of a gentle illustration for that page
  (empty on SPLIT pages; each branch has its own).
- "choices": the answers, only on INTERACTION pages; otherwise an empty list.
- "branches": only on SPLIT pages, exactly 2 objects, each with "text" and
  "image_prompt"; otherwise an empty list.

Rules for INTERACTION pages:
- Continue the story, then end the text with ONE clear, direct question to the
  child, e.g. "What should Mia pack for the picnic?"
- Choices are short (1 to 5 words), concrete, and easy to picture, and clearly
  different from each other. Do not number them or end them with punctuation.
- There are no right or wrong answers. Every choice is safe, kind, and leads
  somewhere pleasant. Never offer a scary, risky, or "naughty" choice, and never
  make the story disappointed in the child's answer.

Rules for PLACEHOLDER RESPONSE pages:
- Use {$token} exactly once, written exactly like that.
- The sentence must read naturally and grammatically with EVERY choice from the
  interaction page put in place of {$token}. Check each one. Write the choices so
  they fit. Example: choices "a red apple" and "a yellow banana", text
  "Mia put {$token} in her basket. It looked yummy!"

Rules for SPLIT pages:
- The two versions should feel clearly different (a different place, activity,
  or event), each one directly following its own choice.
- Each version has {$sentences}, and its own image_prompt.
- Both versions must end so the next page follows naturally from either one.
  Nothing later in the story may depend on which version was read.

General rules:
- Keep a calm, warm, predictable tone. No scary, loud, or sudden events.
- Avoid idioms and sarcasm; be literal and clear.
- Each page should follow on naturally from the page before.
- Each image_prompt MUST be self-contained: restate the main character's name
  and appearance every time so the illustrations look consistent, and describe
  only that page's scene. Never put {$token} in an image_prompt; on a
  placeholder response page describe a scene that fits every choice.

Return ONLY JSON with keys: title (string) and pages (array of page objects, in
page order).
PROMPT;

        $schema = [
            'type'       => 'OBJECT',
            'properties' => [
                'title' => ['type' => 'STRING'],
                'pages' => [
                    'type'  => 'ARRAY',
                    'items' => [
                        'type'       => 'OBJECT',
                        'properties' => [
                            'page_number'  => ['type' => 'INTEGER'],
                            'text'         => ['type' => 'STRING'],
                            'image_prompt' => ['type' => 'STRING'],
                            'choices'      => ['type' => 'ARRAY', 'items' => ['type' => 'STRING']],
                            'branches'     => [
                                'type'  => 'ARRAY',
                                'items' => [
                                    'type'       => 'OBJECT',
                                    'properties' => [
                                        'text'         => ['type' => 'STRING'],
                                        'image_prompt' => ['type' => 'STRING'],
                                    ],
                                    'required' => ['text', 'image_prompt'],
                                ],
                            ],
                        ],
                        'required' => ['page_number', 'text', 'image_prompt', 'choices', 'branches'],
                    ],
                ],
            ],
            'required' => ['title', 'pages'],
        ];

        /* Ask once; if the reply breaks the plan, ask again and say what was
           wrong. A second bad reply fails the request rather than saving a
           broken book. */
        $problems = [];
        $parsed = null;
        for ($attempt = 1; $attempt <= 2; $attempt++) {
            $fullPrompt = $prompt;
            if ($problems) {
                $fullPrompt .= "\n\nYour previous answer did not follow the plan. Fix these problems:\n- "
                    . implode("\n- ", $problems);
            }
            $parsed = $this->requestJson($fullPrompt, $schema, 0.8);
            $problems = $this->checkInteractivePages($parsed['pages'] ?? null, $plan);
            if (!$problems) {
                break;
            }
            Log::warning('[Gemini] generateInteractiveStory plan not followed', [
                'attempt'  => $attempt,
                'problems' => $problems,
            ]);
        }
        if ($problems) {
            throw new \RuntimeException('The AI did not follow the interactive story layout. Please try again.');
        }

        // Turn the reply into rows to save.
        $rows = [];
        foreach (array_values($parsed['pages']) as $i => $page) {
            $n = $i + 1;
            $kind = $plan[$n];
            if ($kind === 'split') {
                $branches = array_values(array_filter(
                    (array) $page['branches'],
                    fn ($b) => is_array($b) && trim((string) ($b['text'] ?? '')) !== ''
                ));
                foreach (array_slice($branches, 0, 2) as $b => $branch) {
                    $rows[] = [
                        'page_number'  => $n,
                        'text'         => trim((string) $branch['text']),
                        'image_prompt' => trim((string) ($branch['image_prompt'] ?? '')) ?: trim((string) $branch['text']),
                        'choices'      => null,
                        'is_split'     => false,
                        'branch_index' => $b,
                    ];
                }
                continue;
            }
            $isInteraction = $kind === 'interaction' || $kind === 'interaction_split';
            $text = trim((string) $page['text']);
            $rows[] = [
                'page_number'  => $n,
                'text'         => $text,
                'image_prompt' => trim(str_replace($token, '', (string) ($page['image_prompt'] ?? ''))) ?: $text,
                'choices'      => $isInteraction
                    ? array_slice($this->cleanChoices($page['choices']), 0, $kind === 'interaction_split' ? 2 : 3)
                    : null,
                'is_split'     => $kind === 'interaction_split',
                'branch_index' => null,
            ];
        }

        $title = trim((string) ($parsed['title'] ?? '')) ?: ($topic !== '' ? $topic : 'A Gentle Story');
        Log::info('[Gemini] generateInteractiveStory success', [
            'title' => $title,
            'rows'  => count($rows),
        ]);
        return [
            'title'   => $title,
            // The main path only (first version of each split), for search and music matching.
            'content' => implode("\n\n", array_column(
                array_filter($rows, fn ($r) => $r['branch_index'] === null || $r['branch_index'] === 0),
                'text'
            )),
            'pages'   => $rows,
        ];
    }

    /* Compare the AI's pages with the plan. Returns a list of plain problems
       (empty = fine) that can be sent back to the AI. */
    private function checkInteractivePages($pages, array $plan): array
    {
        $token = \App\Models\AudiobookPage::CHOICE_TOKEN;
        if (!is_array($pages)) {
            return ['"pages" is missing.'];
        }
        $pages = array_values($pages);
        if (count($pages) !== count($plan)) {
            return ['There must be exactly ' . count($plan) . ' pages, but there were ' . count($pages) . '.'];
        }

        $problems = [];
        foreach ($plan as $n => $kind) {
            $page = is_array($pages[$n - 1]) ? $pages[$n - 1] : [];
            $text = trim((string) ($page['text'] ?? ''));
            $choices = $this->cleanChoices($page['choices'] ?? []);

            if ($kind !== 'split' && $text === '') {
                $problems[] = "Page {$n} has no text.";
            }
            if ($kind === 'interaction' && count($choices) < 2) {
                $problems[] = "Page {$n} is an interaction page and needs 2 or 3 choices.";
            }
            if ($kind === 'interaction_split' && count($choices) < 2) {
                $problems[] = "Page {$n} is a split interaction page and needs exactly 2 choices.";
            }
            if ($kind === 'response' && substr_count($text, $token) !== 1) {
                $problems[] = "Page {$n} must contain {$token} exactly once.";
            }
            if ($kind !== 'response' && str_contains($text, $token)) {
                $problems[] = "Only placeholder response pages may contain {$token}; remove it from page {$n}.";
            }
            if ($kind === 'split') {
                $branches = array_values(array_filter(
                    (array) ($page['branches'] ?? []),
                    fn ($b) => is_array($b) && trim((string) ($b['text'] ?? '')) !== ''
                ));
                if (count($branches) < 2) {
                    $problems[] = "Page {$n} is a split page and needs 2 versions in \"branches\", each with text.";
                }
            }
        }
        return $problems;
    }

    // Trimmed, non-empty, de-duplicated answers without trailing punctuation.
    private function cleanChoices($choices): array
    {
        $out = [];
        foreach ((array) $choices as $c) {
            $c = rtrim(trim((string) $c), " .!?,;:");
            if ($c !== '' && !in_array(mb_strtolower($c), array_map('mb_strtolower', $out), true)) {
                $out[] = mb_substr($c, 0, 80);
            }
        }
        return $out;
    }

    // What language to write the story in. Image prompts stay English.
    private function languageRule(?string $language): string
    {
        return match (strtolower($language ?? 'en')) {
            'ms' => "Write the story TEXT (the 'text' field for every page, the 'choices', and the 'title') in Bahasa Malaysia (standard Malay). Keep \"image_prompt\" in English. It goes to the image generator and must stay clear and literal.",
            default => 'Write the story in clear, simple English.',
        };
    }

    /* POST a prompt to the text model with a JSON schema and return the
       decoded reply. Throws with a friendly message on quota or HTTP errors. */
    private function requestJson(string $prompt, array $schema, float $temperature): array
    {
        $response = Http::timeout(90)->post(
            "{$this->base}/{$this->textModel}:generateContent?key={$this->key}",
            [
                'contents' => [
                    ['parts' => [['text' => $prompt]]],
                ],
                'generationConfig' => [
                    'temperature'      => $temperature,
                    'responseMimeType' => 'application/json',
                    'responseSchema'   => $schema,
                ],
            ]
        );

        if ($response->status() === 429) {
            Log::warning('[Gemini] requestJson quota exceeded (429)', ['body' => $response->body()]);
            throw new \RuntimeException($this->quotaMessage($response->json()));
        }
        if (!$response->successful()) {
            Log::error('[Gemini] requestJson HTTP error', [
                'status' => $response->status(),
                'body'   => $response->body(),
            ]);
            throw new \RuntimeException('Gemini text generation failed (HTTP ' . $response->status() . ')');
        }

        $text = data_get($response->json(), 'candidates.0.content.parts.0.text');
        $parsed = $text ? json_decode($text, true) : null;
        if (!is_array($parsed)) {
            throw new \RuntimeException('Gemini returned no usable content');
        }
        return $parsed;
    }

    // Make a picture with Gemini. Needs a billing-enabled key.
    private function generateWithGemini(string $fullPrompt): ?string
    {
        Log::info('[Gemini] generateWithGemini calling API', [
            'model' => $this->imageModel,
        ]);
        try {
            $response = Http::timeout(90)->post(
                "{$this->base}/{$this->imageModel}:generateContent?key={$this->key}",
                [
                    'contents' => [
                        ['parts' => [['text' => $fullPrompt]]],
                    ],
                    'generationConfig' => [
                        // Image only. Skip the text to save tokens.
                        'responseModalities' => ['IMAGE'],
                    ],
                ]
            );

            if (!$response->successful()) {
                Log::warning('[Gemini] image HTTP error', [
                    'status' => $response->status(),
                    'body'   => $response->body(),
                ]);
                $this->lastImageError = $this->imageErrorMessage($response->status(), $response->json());
                return null;
            }

            $parts = data_get($response->json(), 'candidates.0.content.parts', []);
            foreach ($parts as $part) {
                $data = $part['inlineData']['data'] ?? $part['inline_data']['data'] ?? null;
                if ($data) {
                    $binary = base64_decode($data, true);
                    if ($binary === false) {
                        continue;
                    }
                    /* Gemini's PNGs are 1024x1024 (~1.5 MB). Shrink to
                       ~768px JPEG (~120-200 KB) so pages load faster. */
                    [$saveBytes, $ext] = $this->shrinkForWeb($binary);
                    $path = 'uploads/covers/' . Str::uuid() . '.' . $ext;
                    Storage::disk('public')->put($path, $saveBytes);
                    return 'storage/' . $path;
                }
            }

            Log::warning('[Gemini] image returned no inline image data');
            $this->lastImageError = 'The AI did not return an image. Please try a different topic.';
            return null;
        } catch (\Throwable $e) {
            Log::warning('[Gemini] image exception', ['error' => $e->getMessage()]);
            $this->lastImageError = 'Image generation timed out or failed. The story was saved without a picture.';
            return null;
        }
    }

    // Turn an image API error into a short message for the caregiver.
    private function imageErrorMessage(int $status, ?array $json): string
    {
        if ($status === 429) {
            return 'Image generation is not available on the free Gemini tier'
                . ' (quota is 0). Enable billing on your Google AI Studio key to'
                . ' generate pictures, or add your own image. The story text was saved.';
        }
        if ($status === 404) {
            return 'The configured image model was not found. Set'
                . ' GEMINI_IMAGE_MODEL=gemini-2.5-flash-image in the backend .env.';
        }
        $apiMessage = (string) data_get($json, 'error.message', '');
        return $apiMessage !== ''
            ? "Image generation failed: {$apiMessage}"
            : "Image generation failed (HTTP {$status}). The story text was saved.";
    }

    /* Build a friendly message from a 429 (quota) reply. Includes the
       retry delay if the API tells us one. */
    private function quotaMessage(?array $json): string
    {
        $seconds = null;
        foreach (data_get($json, 'error.details', []) as $detail) {
            if (($detail['@type'] ?? '') === 'type.googleapis.com/google.rpc.RetryInfo') {
                $seconds = (int) rtrim((string) ($detail['retryDelay'] ?? ''), 's');
            }
        }

        $msg = "AI quota reached for model {$this->textModel}.";
        if ($seconds) {
            $msg .= " Please try again in about {$seconds}s.";
        }
        $msg .= ' If this keeps happening, the free-tier quota for this key may be 0 -'
            . ' try a different model (e.g. gemini-2.5-flash) or check your Gemini plan.';

        return $msg;
    }

    /* Shrink image bytes to a max edge and re-encode as JPEG.
       Returns [bytes, extension]. Falls back to the original PNG if GD
       isn't there or something fails. So image gen never breaks. */
    private function shrinkForWeb(string $original, int $maxEdge = 768, int $quality = 82): array
    {
        if (!function_exists('imagecreatefromstring')) {
            return [$original, 'png'];
        }
        $src = @imagecreatefromstring($original);
        if (!$src) {
            return [$original, 'png'];
        }
        $dst = null;
        try {
            $w = imagesx($src);
            $h = imagesy($src);
            if ($w <= 0 || $h <= 0) {
                return [$original, 'png'];
            }
            $ratio = min(1.0, $maxEdge / max($w, $h));
            $tw = max(1, (int) round($w * $ratio));
            $th = max(1, (int) round($h * $ratio));
            $dst = imagecreatetruecolor($tw, $th);
            if (!$dst) {
                return [$original, 'png'];
            }
            // JPEG has no alpha. Paint white first so PNG transparency
            // becomes white instead of black.
            $white = imagecolorallocate($dst, 255, 255, 255);
            imagefilledrectangle($dst, 0, 0, $tw, $th, $white);
            imagecopyresampled($dst, $src, 0, 0, 0, 0, $tw, $th, $w, $h);
            ob_start();
            $ok = imagejpeg($dst, null, $quality);
            $jpeg = (string) ob_get_clean();
            if (!$ok || $jpeg === '') {
                return [$original, 'png'];
            }
            return [$jpeg, 'jpg'];
        } catch (\Throwable $e) {
            Log::warning('Image shrink failed', ['error' => $e->getMessage()]);
            return [$original, 'png'];
        } finally {
            if ($src) {
                imagedestroy($src);
            }
            if ($dst) {
                imagedestroy($dst);
            }
        }
    }
}
