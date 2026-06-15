<?php

namespace App\Http\Controllers\Api;

use App\Services\GeminiService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class TtsController extends ApiController
{
    // Match the app's voice names to Gemini's voices.
    private const VOICE_MAP = [
        'calm_female'    => 'Kore',   // firm, warm female
        'gentle_female'  => 'Leda',   // soft, youthful female
        'warm_male'      => 'Orus',   // warm male
        'friendly_child' => 'Puck',   // upbeat, playful
        'soothing_elder' => 'Charon', // deep, calm
    ];

    /* Make a voice clip for a page of text with Gemini TTS.
       Returns a URL to a cached WAV the app can play. */
    public function speak(Request $request, GeminiService $gemini): JsonResponse
    {
        $this->logEvent('Tts', 'speak called', [
            'voice'       => $request->input('voice'),
            'text_length' => strlen((string) $request->input('text')),
        ]);

        $validator = Validator::make($request->all(), [
            'text'  => 'required|string|max:2000',
            'voice' => 'nullable|string',
        ]);

        if ($validator->fails()) {
            $this->logWarn('Tts', 'speak validation failed', [
                'errors' => $validator->errors()->all(),
            ]);
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        if (!$gemini->isConfigured()) {
            $this->logWarn('Tts', 'speak AI not configured');
            return $this->errorResponse('AI is not configured.', 'AI_NOT_CONFIGURED', 503);
        }

        $voice = self::VOICE_MAP[$request->input('voice')] ?? 'Kore';
        $path = $gemini->generateSpeech($request->input('text'), $voice);

        if (!$path) {
            $this->logWarn('Tts', 'speak generation failed', [
                'voice' => $voice,
            ]);
            return $this->errorResponse(
                'Could not generate the natural voice. Please try again.',
                'TTS_FAILED',
                502
            );
        }

        $this->logEvent('Tts', 'speak success', [
            'voice' => $voice,
            'path'  => $path,
        ]);
        return $this->successResponse('OK', ['audio_url' => url($path)]);
    }
}
