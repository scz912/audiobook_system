<?php

namespace App\Http\Controllers\Api;

use App\Models\Audiobook;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Validator;

class AudiobookController extends ApiController
{
    /*Get Audiobook data by ID, including its pages 
    and associated music track if available*/
    public function getAudiobookData(Request $request, string $audiobookId): JsonResponse
    {
        $this->logEvent('Audiobook', 'getAudiobookData called', [
            'audiobook_id' => $audiobookId,
        ]);
        try {
            $validator = Validator::make(
                ['audiobook_id' => $audiobookId],
                ['audiobook_id' => 'required|string|uuid']
            );

            if ($validator->fails()) {
                $this->logWarn('Audiobook', 'getAudiobookData invalid uuid', [
                    'audiobook_id' => $audiobookId,
                ]);
                return $this->errorResponse(
                    'Validation failed: ' . implode(', ', $validator->errors()->all()),
                    'VALIDATION_ERROR',
                    422
                );
            }

            $audiobook = Audiobook::with('musicTrack')->where('audiobook_id', $audiobookId)->first();

            if (!$audiobook) {
                $this->logWarn('Audiobook', 'getAudiobookData not found', [
                    'audiobook_id' => $audiobookId,
                ]);
                return $this->errorResponse('Audiobook not found.', 'AUDIOBOOK_NOT_FOUND', 404);
            }

            $this->logEvent('Audiobook', 'getAudiobookData success', [
                'audiobook_id' => $audiobook->audiobook_id,
                'pages'        => $audiobook->pages->count(),
            ]);
            return $this->successResponse('Audiobook data retrieved successfully', [
                'audiobook_id'     => $audiobook->audiobook_id,
                'title'            => $audiobook->title,
                'author'           => $audiobook->author,
                'description'      => $audiobook->description,
                'topic'            => $audiobook->topic,
                'category'         => $audiobook->category,
                'difficulty'       => $audiobook->difficulty,
                'type'             => $audiobook->type,
                'content_text'     => $audiobook->content_text,
                'audio_file'       => $this->mediaUrl($audiobook->audio_file),
                'video_file'       => $this->mediaUrl($audiobook->video_file),
                'cover_image'      => $this->mediaUrl($audiobook->cover_image),
                'duration_minutes' => $audiobook->duration_minutes,
                'language'         => $audiobook->language,
                'age_group'        => $audiobook->age_group,
                'tags'             => $audiobook->tags,
                'is_generated'     => (bool) $audiobook->is_generated,
                'is_user_uploaded' => (bool) $audiobook->is_user_uploaded,
                'status'           => $audiobook->status,
                'pages'            => $audiobook->pages->map(fn ($p) => [
                    'page_id'        => $p->page_id,
                    'page_number'    => $p->page_number,
                    'text'           => $p->text,
                    'image'          => $this->mediaUrl($p->image),
                    'audio_start_ms' => $p->audio_start_ms,
                ])->toArray(),
                'track_id'         => $audiobook->track_id,
                'bgm_volume'       => $audiobook->bgm_volume ?? 30,
                'music_track'      => $audiobook->musicTrack ? [
                    'track_id'     => $audiobook->musicTrack->track_id,
                    'title'        => $audiobook->musicTrack->title,
                    'composer'     => $audiobook->musicTrack->composer,
                    'file_url'     => $this->mediaUrl($audiobook->musicTrack->file_path),
                    'tags'         => $audiobook->musicTrack->tagsArray(),
                    'tempo'        => $audiobook->musicTrack->tempo,
                    'duration_secs'=> $audiobook->musicTrack->duration_secs,
                ] : null,
                'created_at'       => $audiobook->created_at
                    ? Carbon::parse($audiobook->created_at)->format('Y-m-d H:i:s')
                    : null,
                'updated_at'       => $audiobook->updated_at
                    ? Carbon::parse($audiobook->updated_at)->format('Y-m-d H:i:s')
                    : null,
            ]);
        } catch (\Throwable $e) {
            $this->logError('Audiobook', 'getAudiobookData exception', [
                'audiobook_id' => $audiobookId ?? 'unknown',
                'error'        => $e->getMessage(),
            ]);
            return $this->errorResponse('Internal server error', 'SERVER_ERROR', 500);
        }
    }

}
