<?php

namespace App\Http\Controllers\Api;

use App\Models\Audiobook;
use App\Models\Caregiver;
use App\Models\HubComment;
use App\Models\HubLike;
use App\Models\HubPost;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class HubController extends ApiController
{
    // The shared-audiobook feed, newest first. Members only — never public.
    public function feed(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        if ($resp = $this->ensureMember($caregiver)) {
            return $resp;
        }

        $posts = HubPost::orderByDesc('created_at')->limit(50)->get();
        $out = $posts->map(fn ($p) => $this->serializePost($p, $caregiver->caregiver_id))
            ->filter(fn ($p) => $p !== null)
            ->values();
        return $this->successResponse('OK', $out);
    }

    // Share one of my audiobooks to the hub.
    public function create(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        if ($resp = $this->ensureMember($caregiver)) {
            return $resp;
        }

        $validator = Validator::make($request->all(), [
            'audiobook_id'  => 'required|uuid',
            'caption'       => 'nullable|string|max:300',
            'include_music' => 'nullable|boolean',
        ]);
        if ($validator->fails()) {
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $book = Audiobook::where('audiobook_id', $request->input('audiobook_id'))->first();
        if (!$book) {
            return $this->errorResponse('Audiobook not found', 'NOT_FOUND', 404);
        }

        $post = HubPost::create([
            'audiobook_id'  => $book->audiobook_id,
            'shared_by'     => $caregiver->caregiver_id,
            'caption'       => $request->input('caption'),
            'include_music' => $request->boolean('include_music'),
        ]);

        $this->logEvent('Hub', 'post created', ['post_id' => $post->post_id]);
        return $this->successResponse('Shared', $this->serializePost($post, $caregiver->caregiver_id));
    }

    // Delete a post I shared.
    public function destroy(Request $request, string $postId): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $post = HubPost::where('post_id', $postId)->first();
        if (!$post) {
            return $this->errorResponse('Post not found', 'NOT_FOUND', 404);
        }
        if ($post->shared_by !== $caregiver->caregiver_id) {
            return $this->errorResponse('Not your post', 'FORBIDDEN', 403);
        }
        $post->delete();
        return $this->successResponse('Deleted');
    }

    // Like a post (no-op if already liked).
    public function like(Request $request, string $postId): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        if ($resp = $this->ensureMember($caregiver)) {
            return $resp;
        }
        if (!HubPost::where('post_id', $postId)->exists()) {
            return $this->errorResponse('Post not found', 'NOT_FOUND', 404);
        }
        HubLike::firstOrCreate([
            'post_id'      => $postId,
            'caregiver_id' => $caregiver->caregiver_id,
        ]);
        return $this->successResponse('Liked', [
            'like_count' => HubLike::where('post_id', $postId)->count(),
            'liked'      => true,
        ]);
    }

    // Remove my like from a post.
    public function unlike(Request $request, string $postId): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        HubLike::where('post_id', $postId)
            ->where('caregiver_id', $caregiver->caregiver_id)
            ->delete();
        return $this->successResponse('Unliked', [
            'like_count' => HubLike::where('post_id', $postId)->count(),
            'liked'      => false,
        ]);
    }

    // Comments on a post, oldest first.
    public function comments(Request $request, string $postId): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        if ($resp = $this->ensureMember($caregiver)) {
            return $resp;
        }
        $rows = HubComment::where('post_id', $postId)->orderBy('created_at')->get();
        $authors = Caregiver::whereIn('caregiver_id', $rows->pluck('caregiver_id'))->get()->keyBy('caregiver_id');
        $out = $rows->map(fn ($c) => $this->serializeComment($c, $authors[$c->caregiver_id] ?? null));
        return $this->successResponse('OK', $out);
    }

    // Add a comment to a post.
    public function addComment(Request $request, string $postId): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        if ($resp = $this->ensureMember($caregiver)) {
            return $resp;
        }
        if (!HubPost::where('post_id', $postId)->exists()) {
            return $this->errorResponse('Post not found', 'NOT_FOUND', 404);
        }

        $validator = Validator::make($request->all(), [
            'body' => 'required|string|max:1000',
        ]);
        if ($validator->fails()) {
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $comment = HubComment::create([
            'post_id'      => $postId,
            'caregiver_id' => $caregiver->caregiver_id,
            'body'         => trim($request->input('body')),
        ]);
        return $this->successResponse('Commented', $this->serializeComment($comment, $caregiver));
    }

    // Delete my own comment.
    public function deleteComment(Request $request, string $postId, string $commentId): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $comment = HubComment::where('comment_id', $commentId)
            ->where('post_id', $postId)
            ->first();
        if (!$comment) {
            return $this->errorResponse('Comment not found', 'NOT_FOUND', 404);
        }
        if ($comment->caregiver_id !== $caregiver->caregiver_id) {
            return $this->errorResponse('Not your comment', 'FORBIDDEN', 403);
        }
        $comment->delete();
        return $this->successResponse('Deleted');
    }

    // Full post shape for the feed. Returns null if the book was deleted.
    private function serializePost(HubPost $post, string $meId): ?array
    {
        $book = Audiobook::where('audiobook_id', $post->audiobook_id)->first();
        if (!$book) {
            return null;
        }
        $author = Caregiver::where('caregiver_id', $post->shared_by)->first();

        return [
            'post_id'       => $post->post_id,
            'caption'       => $post->caption,
            'include_music' => (bool) $post->include_music,
            'created_at'    => $post->created_at?->toIso8601String(),
            'author'        => $author ? [
                'caregiver_id' => $author->caregiver_id,
                'name'         => $author->name,
                'avatar_emoji' => $author->avatar_emoji,
                'avatar_color' => $author->avatar_color,
            ] : null,
            'audiobook'     => [
                'audiobook_id' => $book->audiobook_id,
                'title'        => $book->title,
                'author'       => $book->author,
                'language'     => $book->language,
                'cover_image'  => $this->mediaUrl($book->cover_image),
            ],
            'like_count'    => HubLike::where('post_id', $post->post_id)->count(),
            'comment_count' => HubComment::where('post_id', $post->post_id)->count(),
            'liked_by_me'   => HubLike::where('post_id', $post->post_id)
                ->where('caregiver_id', $meId)->exists(),
            'is_mine'       => $post->shared_by === $meId,
        ];
    }

    private function serializeComment(HubComment $c, ?Caregiver $author): array
    {
        return [
            'comment_id' => $c->comment_id,
            'body'       => $c->body,
            'created_at' => $c->created_at?->toIso8601String(),
            'author'     => $author ? [
                'caregiver_id' => $author->caregiver_id,
                'name'         => $author->name,
                'avatar_emoji' => $author->avatar_emoji,
                'avatar_color' => $author->avatar_color,
            ] : null,
            'is_mine'    => $author?->caregiver_id === $c->caregiver_id,
        ];
    }
}
