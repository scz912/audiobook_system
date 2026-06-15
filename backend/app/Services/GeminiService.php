<?php

namespace App\Services;

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
        Log::info('[Gemini] generateSpeech cache miss — calling Gemini TTS', [
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
       on error — the caller falls back to the cached row. */
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
- For narrator_voice: one of "calm_female", "gentle_female", "warm_male",
  "friendly_child", "soothing_elder".
- For volume: a number between 0.0 and 1.0 (step 0.05).
- For text_scale: a number between 0.7 and 2.0 (step 0.05).
- For auto_play_next, read_along: true or false.
- Each item's "reason" must be one short, plain sentence a caregiver can read
  in a glance. No clinical claims, no jargon. Reference the specific stat you
  used (e.g. "Pause rate is high (3.4 per session)…").
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
                                        ],
                                        'required' => ['setting_key', 'suggested_value', 'reason'],
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
                $clean[] = [
                    'setting_key'     => $key,
                    'suggested_value' => $raw,
                    'reason'          => $reason,
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

    // Add a soft, calm illustration style to the prompt.
    private function styledPrompt(string $prompt): string
    {
        return 'A soft, calming, child-friendly storybook illustration. '
            . 'Gentle pastel colours, simple rounded shapes, no text, nothing scary. '
            . 'Scene: ' . $prompt;
    }

    // Make a paged, autism-friendly story.
    public function generateStory(string $topic, ?string $ageGroup, ?string $sourceText, ?int $pageCount = null, ?string $language = null): array
    {
        Log::info('[Gemini] generateStory called', [
            'topic'      => $topic,
            'age_group'  => $ageGroup,
            'page_count' => $pageCount,
            'language'   => $language,
            'model'      => $this->textModel,
        ]);
        $age = $ageGroup ?: '7-9';
        $instruction = ($sourceText !== null && trim($sourceText) !== '')
            ? "Rewrite the following text into a calming, autism-friendly children's story.\n\nTEXT:\n" . trim($sourceText)
            : "Write a calming, autism-friendly children's story about: {$topic}";

        /* Use the caregiver's page count if given. Otherwise keep it small
           since each page is a separate image (~12s). */
        $lengthRule = ($pageCount !== null && $pageCount > 0)
            ? "Split the story into exactly {$pageCount} short pages, like a picture book."
            : 'Split the story into between 4 and 6 short pages, like a picture book — '
                . 'choose a sensible length for the topic and age.';

        /* Tell Gemini what language to write in. Image prompts stay English
           so the image model gets clear, simple words. */
        $code = strtolower($language ?? 'en');
        $languageRule = match ($code) {
            'ms' => "Write the story TEXT (the 'text' field for every page, and the 'title') in Bahasa Malaysia (standard Malay). Keep \"image_prompt\" in English — it goes to the image generator and must stay clear and literal.",
            default => 'Write the story in clear, simple English.',
        };

        $prompt = <<<PROMPT
You are an author creating gentle, sensory-friendly stories for autistic children aged {$age}.
{$instruction}

Stay close to what the reader asked for: keep the characters, setting, and ideas
they described, and make the story actually about their request.

{$languageRule}

{$lengthRule}
For each page give:
- "text": one or two very short, simple sentences for that page.
- "image_prompt": a clear description of a gentle illustration for THAT page's scene.

Rules:
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
            // No usable pages — use the whole reply as one page.
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
                        // Image only — skip the text to save tokens.
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
        $msg .= ' If this keeps happening, the free-tier quota for this key may be 0 —'
            . ' try a different model (e.g. gemini-2.5-flash) or check your Gemini plan.';

        return $msg;
    }

    /* Shrink image bytes to a max edge and re-encode as JPEG.
       Returns [bytes, extension]. Falls back to the original PNG if GD
       isn't there or something fails — so image gen never breaks. */
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
            // JPEG has no alpha — paint white first so PNG transparency
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
