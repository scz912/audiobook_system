<?php

namespace App\Jobs;

use App\Models\Audiobook;
use App\Services\GeminiService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

/* Draws the page pictures for an AI storybook in the background.
   The book starts as "processing"; this job makes each picture with
   Gemini and sets the book to "available" once they're all done.
   Needs a queue worker: php artisan queue:work */
class GenerateAudiobookImages implements ShouldQueue
{
    use Dispatchable;
    use InteractsWithQueue;
    use Queueable;
    use SerializesModels;

    // Plenty of time — image requests are slow.
    public int $timeout = 1200;
    public int $tries = 1;

    public function __construct(public string $audiobookId)
    {
    }

    public function handle(GeminiService $gemini): void
    {
        Log::info('[ImageJob] handle started', [
            'audiobook_id' => $this->audiobookId,
        ]);
        $book = Audiobook::with('pages')->find($this->audiobookId);
        if (!$book) {
            Log::warning('[ImageJob] book not found', [
                'audiobook_id' => $this->audiobookId,
            ]);
            return;
        }

        $coverImagePath = null;
        $succeeded = 0;
        $failed = 0;

        // Build every page's prompt, then draw all the pictures at once.
        $prompts = [];
        foreach ($book->pages as $page) {
            $prompts[] = $page->image_prompt !== null && $page->image_prompt !== ''
                ? $page->image_prompt
                : (string) $page->text;
        }
        $paths = $gemini->downloadImages($prompts);

        foreach ($book->pages as $i => $page) {
            $path = $paths[$i] ?? null;
            $page->image = $path;
            $page->save();

            if ($path !== null) {
                $succeeded++;
            } else {
                $failed++;
            }

            $coverImagePath ??= $path;
        }

        $book->cover_image = $coverImagePath;
        $book->status = 'available';
        $book->save();

        Log::info('[ImageJob] handle finished', [
            'audiobook_id' => $book->audiobook_id,
            'pages'        => $book->pages->count(),
            'succeeded'    => $succeeded,
            'failed'       => $failed,
        ]);
    }

    // If the job crashes, don't leave the book stuck on "processing".
    public function failed(\Throwable $e): void
    {
        $book = Audiobook::find($this->audiobookId);
        if ($book) {
            $book->status = 'available';
            $book->save();
        }
        Log::error('[ImageJob] job failed', [
            'audiobook_id' => $this->audiobookId,
            'error'        => $e->getMessage(),
        ]);
    }
}
