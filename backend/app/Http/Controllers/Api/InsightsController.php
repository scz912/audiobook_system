<?php

namespace App\Http\Controllers\Api;

use App\Models\AiSuggestion;
use App\Models\ChildProfile;
use App\Models\ChildSettings;
use App\Models\ListeningHistory;
use App\Services\GeminiService;
use App\Services\SettingsAdvisor;
use App\Services\TipLearner;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class InsightsController extends ApiController
{
    private const TZ = 'Asia/Kuala_Lumpur';

    /* Settings a tip may change, with checks for each value.
       Anything else gets dropped. Each check returns
       [true, value] if OK, or [false, null] if out of range. */
    private function settingValidators(): array
    {
        return [
            'reading_speed' => function ($v): array {
                if (!is_numeric($v)) {
                    return [false, null];
                }
                $f = round((float) $v, 2);
                return $f >= 0.5 && $f <= 2.0 ? [true, $f] : [false, null];
            },
            'volume' => function ($v): array {
                if (!is_numeric($v)) {
                    return [false, null];
                }
                $f = round((float) $v, 2);
                return $f >= 0.0 && $f <= 1.0 ? [true, $f] : [false, null];
            },
            'text_scale' => function ($v): array {
                if (!is_numeric($v)) {
                    return [false, null];
                }
                $f = round((float) $v, 2);
                return $f >= 0.7 && $f <= 2.0 ? [true, $f] : [false, null];
            },
            'narrator_voice' => function ($v): array {
                $s = is_string($v) ? trim($v) : '';
                return in_array($s, ChildSettings::ALLOWED_VOICES, true)
                    ? [true, $s]
                    : [false, null];
            },
            'auto_play_next'     => fn ($v) => [true, $this->coerceBool($v)],
            'read_along'         => fn ($v) => [true, $this->coerceBool($v)],
        ];
    }

    private function coerceBool(mixed $v): bool
    {
        if (is_bool($v)) {
            return $v;
        }
        if (is_string($v)) {
            return in_array(strtolower(trim($v)), ['true', '1', 'yes', 'on'], true);
        }
        return (bool) $v;
    }

    /* Listening insights for the signed-in caregiver:
       totals, avg session, streak, last 7 days, top stories,
       recent activity, and the same fields per child. */
    public function overview(Request $request): JsonResponse
    {
        $caregiver = $request->get('auth_caregiver');
        $this->logEvent('Insights', 'overview called', [
            'caregiver_id' => $caregiver?->caregiver_id,
            'child_id'     => $request->input('child_id'),
        ]);
        /* The 'children' list always has every profile (the selector needs
           them). $scopedProfiles is what the queries use, narrowed to one
           child when child_id is passed. */
        $allProfiles = $caregiver->childProfiles()->orderBy('created_at')->get();
        $filterChildId = $request->input('child_id');
        $scopedProfiles = $filterChildId
            ? $allProfiles->where('child_id', $filterChildId)->values()
            : $allProfiles;
        if ($filterChildId && $scopedProfiles->isEmpty()) {
            $this->logWarn('Insights', 'overview child not found', [
                'child_id' => $filterChildId,
            ]);
            return $this->errorResponse('Child profile not found', 'NOT_FOUND', 404);
        }
        $profiles = $scopedProfiles;
        $childIds = $profiles->pluck('child_id')->all();

        $now = Carbon::now(self::TZ);
        $week = $this->emptyWeek($now);

        $moods = ['happy', 'calm', 'curious', 'sleepy'];
        $moodTotals = array_fill_keys($moods, 0);

        $totalMinutes = 0;
        $totalSeconds = 0;
        $totalSessions = 0;
        $totalCompleted = 0;
        $children = [];

        foreach ($profiles as $p) {
            $sessions = $p->listeningHistory()
                ->orderByDesc('created_at')
                ->get();
            $count = $sessions->count();
            $completed = $sessions->where('completed', true)->count();
            $childSeconds = (int) $sessions->sum('duration_seconds');
            $childMinutes = (int) $p->listening_minutes;

            $totalMinutes += $childMinutes;
            $totalSeconds += $childSeconds;
            $totalSessions += $count;
            $totalCompleted += $completed;

            $childMoods = array_fill_keys($moods, 0);
            $childDays = [];
            foreach ($sessions as $s) {
                if ($s->mood && isset($childMoods[$s->mood])) {
                    $childMoods[$s->mood]++;
                    $moodTotals[$s->mood]++;
                }
                $dayKey = $this->dayKey($s->created_at);
                $childDays[$dayKey] = true;
                if (isset($week[$dayKey])) {
                    $week[$dayKey]['minutes'] += (int) round($s->duration_seconds / 60);
                }
            }

            $children[] = [
                'child_id'            => $p->child_id,
                'name'                => $p->name,
                'avatar_emoji'        => $p->avatar_emoji,
                'avatar_color'        => $p->avatar_color,
                'favorite_genre'      => $p->favorite_genre,
                'listening_minutes'   => $childMinutes,
                'sessions'            => $count,
                'completed'           => $completed,
                'completion_rate'     => $count > 0 ? (int) round($completed / $count * 100) : 0,
                'top_mood'            => $this->topMood($childMoods),
                'avg_session_minutes' => $count > 0 ? round($childSeconds / $count / 60, 1) : 0.0,
                'streak_days'         => $this->computeStreak(array_keys($childDays), $now),
            ];
        }

        $allDayKeys = $this->collectDayKeys($childIds);

        return $this->successResponse('OK', [
            'total_children'          => $profiles->count(),
            'total_listening_minutes' => $totalMinutes,
            'total_sessions'          => $totalSessions,
            'completed_sessions'      => $totalCompleted,
            'completion_rate'         => $totalSessions > 0
                ? (int) round($totalCompleted / $totalSessions * 100)
                : 0,
            'top_mood'                => $this->topMood($moodTotals),
            'mood_breakdown'          => $moodTotals,
            'avg_session_minutes'     => $totalSessions > 0
                ? round($totalSeconds / $totalSessions / 60, 1)
                : 0.0,
            'streak_days'             => $this->computeStreak($allDayKeys, $now),
            'last_seven_days'         => array_values($week),
            'top_stories'             => $this->topStories($childIds),
            'recent_sessions'         => $this->recentSessions($childIds),
            'children'                => $children,
        ]);
    }

    /* Works out setting tips for a child in three steps, then saves them:
       1. rules (SettingsAdvisor) find candidates from the listening, with
          the child's own choices first and recent sessions counting more;
       2. learning (TipLearner) ranks them by what has worked before, from
          caregivers' answers and from whether applied tips helped;
       3. AI review (Gemini) picks and words the best few for this child,
          within guardrails; without it, the learned order is used.
       Few sessions -> confidence "low". */
    public function analyse(Request $request, string $childId): JsonResponse
    {
        $this->logEvent('Insights', 'analyse called', [
            'child_id' => $childId,
        ]);
        $profile = $this->ownedProfile($request, $childId);
        if (!$profile) {
            $this->logWarn('Insights', 'analyse child not found', [
                'child_id' => $childId,
            ]);
            return $this->errorResponse('Child profile not found', 'NOT_FOUND', 404);
        }

        $settings = $profile->childSettings
            ?? ChildSettings::create(['child_id' => $profile->child_id]);
        $saved = [
            'narrator_voice'     => $settings->narrator_voice,
            'reading_speed'      => (float) $settings->reading_speed,
            'volume'             => (float) $settings->volume,
            'text_scale'         => (float) $settings->text_scale,
            'reduced_animations' => (bool) $settings->reduced_animations,
            'auto_play_next'     => (bool) $settings->auto_play_next,
            'read_along'         => (bool) $settings->read_along,
        ];

        $now = Carbon::now(self::TZ);
        $advisor = app(SettingsAdvisor::class);
        $learner = app(TipLearner::class);

        // 0. Learn from tips applied earlier that have had time to work.
        $judged = $learner->evaluateOutcomes($profile, $advisor, $now);

        // 1. Rules: every candidate tip, with the evidence behind it.
        $sessions = $profile->listeningHistory()
            ->where('created_at', '>=', $now->copy()->subDays(SettingsAdvisor::WINDOW_DAYS))
            ->get();
        $advice = $advisor->advise($sessions, $saved, $now, null);
        $stats = $advice['stats'] + ['current_settings' => $saved];
        $confidence = $advice['confidence'];

        // Only known settings, safe values, and real changes (guardrails).
        $validators = $this->settingValidators();
        $candidates = [];
        foreach ($advice['items'] as $raw) {
            $key = $raw['setting_key'];
            if (!isset($validators[$key])) {
                continue;
            }
            [$ok, $value] = $validators[$key]($raw['suggested_value']);
            $current = $saved[$key] ?? null;
            if (!$ok || $this->valuesEqual($current, $value)) {
                continue;
            }
            $candidates[] = [
                'id'              => (string) Str::uuid(),
                'setting_key'     => $key,
                'current_value'   => $current,
                'suggested_value' => $value,
                'reason'          => $raw['reason'],
                'reason_ms'       => $raw['reason_ms'] ?? $raw['reason'],
                'strength'        => $raw['strength'] ?? 0.5,
                'arm'             => TipLearner::arm($key, $current, $value),
            ];
        }

        // 2. Learning: rank by what has worked before (Thompson sampling).
        $ranked = $learner->rank($profile->child_id, $candidates);

        // 3. AI review: Gemini picks and words the best few, if it can.
        [$items, $aiChecked] = $this->aiReview($profile, $stats, $ranked);
        $items = array_map(fn ($c) => [
            'id'              => $c['id'],
            'setting_key'     => $c['setting_key'],
            'current_value'   => $c['current_value'],
            'suggested_value' => $c['suggested_value'],
            'reason'          => $c['reason'],
            'reason_ms'       => $c['reason_ms'],
            'strength'        => $c['strength'],
            'arm'             => $c['arm'],
            'learning'        => $c['learning'] ?? null,
            'ai_checked'      => $aiChecked,
            'status'          => 'pending',
        ], $items);

        $stats['pipeline'] = [
            'candidates'        => count($candidates),
            'after_learning'    => count($ranked),
            'ai_checked'        => $aiChecked,
            'outcomes_judged'   => $judged,
        ];

        $row = AiSuggestion::updateOrCreate(
            ['child_id' => $profile->child_id],
            [
                'source_stats' => $stats,
                'items'        => $items,
                'confidence'   => $confidence,
                'is_stale'     => false,
                'generated_at' => now(),
            ]
        );

        $this->logEvent('Insights', 'analyse success', [
            'child_id'   => $childId,
            'candidates' => count($candidates),
            'kept'       => count($items),
            'ai_checked' => $aiChecked,
        ]);
        return $this->successResponse('Suggestions ready',
            $this->serializeSuggestion($row));
    }

    /* Step 3 of the tips: Gemini reviews the learned ranking with the
       child's context and returns [items, aiChecked]. Guardrails: only
       candidate ids are accepted, each once, at most MAX_TIPS, values stay
       ours, and reasons are trimmed. If Gemini is off, fails or picks
       nothing usable, the learned order is kept (aiChecked = false). */
    private function aiReview(ChildProfile $profile, array $stats, array $ranked): array
    {
        $fallback = [array_slice($ranked, 0, SettingsAdvisor::MAX_TIPS), false];
        if ($ranked === []) {
            return $fallback;
        }

        $shortlist = array_slice($ranked, 0, 5);
        $picks = app(GeminiService::class)->reviewSettingTips(
            [
                'age'               => $profile->age,
                'sessions'          => $stats['sessions_count'],
                'completion_rate'   => $stats['completion_rate'],
                'struggle'          => $stats['struggle'],
                'back_per_page'     => $stats['back_per_page'],
                'pauses_per_minute' => $stats['pauses_per_minute'],
                'moods'             => $stats['mood_breakdown'],
                'settings_now'      => $stats['current_settings'],
            ],
            array_map(fn ($c) => [
                'id'            => $c['id'],
                'setting'       => $c['setting_key'],
                'from'          => $c['current_value'],
                'to'            => $c['suggested_value'],
                'rule_reason'   => $c['reason'],
                'rule_strength' => $c['strength'],
                'learned_trust' => $c['learning']['trust'] ?? null,
                'helped'        => $c['learning']['helped'] ?? 0,
                'tried'         => $c['learning']['tried'] ?? 0,
            ], $shortlist)
        );
        if (!is_array($picks)) {
            return $fallback;
        }

        $byId = array_column($shortlist, null, 'id');
        $chosen = [];
        foreach ($picks as $pick) {
            $id = is_array($pick) ? ($pick['id'] ?? null) : null;
            if (!is_string($id) || !isset($byId[$id]) || isset($chosen[$id])) {
                continue;
            }
            $item = $byId[$id];
            $reason = trim((string) ($pick['reason'] ?? ''));
            $reasonMs = trim((string) ($pick['reason_ms'] ?? ''));
            if ($reason !== '') {
                $item['reason'] = mb_substr($reason, 0, 120);
            }
            if ($reasonMs !== '') {
                $item['reason_ms'] = mb_substr($reasonMs, 0, 120);
            }
            $chosen[$id] = $item;
            if (count($chosen) >= SettingsAdvisor::MAX_TIPS) {
                break;
            }
        }
        return $chosen === [] ? $fallback : [array_values($chosen), true];
    }

    /* The last saved tips for a child (nothing is worked out again). The insights page
       shows these right away instead of waiting for a fresh analyse. */
    public function suggestions(Request $request, string $childId): JsonResponse
    {
        $this->logEvent('Insights', 'suggestions called', [
            'child_id' => $childId,
        ]);
        $profile = $this->ownedProfile($request, $childId);
        if (!$profile) {
            $this->logWarn('Insights', 'suggestions child not found', [
                'child_id' => $childId,
            ]);
            return $this->errorResponse('Child profile not found', 'NOT_FOUND', 404);
        }
        $cached = AiSuggestion::where('child_id', $profile->child_id)->first();
        if (!$cached) {
            $this->logEvent('Insights', 'suggestions empty (no cache)', [
                'child_id' => $childId,
            ]);
            return $this->successResponse('No suggestions yet', [
                'suggestion_id' => null,
                'child_id'      => $profile->child_id,
                'confidence'    => 'normal',
                'is_stale'      => false,
                'generated_at'  => null,
                'source_stats'  => null,
                'items'         => [],
            ]);
        }
        return $this->successResponse('OK', $this->serializeSuggestion($cached));
    }

    /* Accept one tip (with an optional edited value) and write it to the
       child's settings. Marks it accepted so the UI can grey it out. */
    public function applySuggestion(Request $request, string $childId): JsonResponse
    {
        $this->logEvent('Insights', 'applySuggestion called', [
            'child_id'    => $childId,
            'item_id'     => $request->input('item_id'),
            'has_override' => $request->has('override_value'),
        ]);
        $profile = $this->ownedProfile($request, $childId);
        if (!$profile) {
            $this->logWarn('Insights', 'applySuggestion child not found', [
                'child_id' => $childId,
            ]);
            return $this->errorResponse('Child profile not found', 'NOT_FOUND', 404);
        }

        $validator = Validator::make($request->all(), [
            'item_id'        => 'required|string',
            'override_value' => 'sometimes|nullable',
        ]);
        if ($validator->fails()) {
            $this->logWarn('Insights', 'applySuggestion validation failed', [
                'errors' => $validator->errors()->all(),
            ]);
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $row = AiSuggestion::where('child_id', $profile->child_id)->first();
        if (!$row) {
            $this->logWarn('Insights', 'applySuggestion no cached row', [
                'child_id' => $childId,
            ]);
            return $this->errorResponse('No suggestions to apply', 'NOT_FOUND', 404);
        }

        $items = $row->items;
        $idx = $this->findItemIndex($items, $request->input('item_id'));
        if ($idx === null) {
            $this->logWarn('Insights', 'applySuggestion item not found', [
                'child_id' => $childId,
                'item_id'  => $request->input('item_id'),
            ]);
            return $this->errorResponse('Suggestion item not found', 'NOT_FOUND', 404);
        }
        $item = $items[$idx];
        if (($item['status'] ?? 'pending') !== 'pending') {
            $this->logWarn('Insights', 'applySuggestion already resolved', [
                'item_id' => $item['id'] ?? null,
                'status'  => $item['status'] ?? null,
            ]);
            return $this->errorResponse('This suggestion has already been resolved',
                'ALREADY_RESOLVED', 409);
        }

        // Check the edited value, or the original tip if not edited.
        $validators = $this->settingValidators();
        $key = (string) $item['setting_key'];
        if (!isset($validators[$key])) {
            $this->logWarn('Insights', 'applySuggestion unknown setting', [
                'setting_key' => $key,
            ]);
            return $this->errorResponse('Unknown setting in suggestion', 'INVALID', 422);
        }
        $rawValue = $request->has('override_value')
            ? $request->input('override_value')
            : ($item['suggested_value'] ?? null);
        [$ok, $value] = $validators[$key]($rawValue);
        if (!$ok) {
            $this->logWarn('Insights', 'applySuggestion value out of range', [
                'setting_key' => $key,
                'raw_value'   => $rawValue,
            ]);
            return $this->errorResponse('Suggested value is out of range', 'INVALID', 422);
        }

        // Save to child_settings.
        $settings = $profile->childSettings
            ?? ChildSettings::create(['child_id' => $profile->child_id]);
        $settings->fill([$key => $value])->save();

        $items[$idx]['status'] = $request->has('override_value') ? 'edited' : 'accepted';
        $items[$idx]['applied_value'] = $value;
        $row->items = $items;
        $row->save();

        /* Learning: the caregiver said yes. Also note how listening is going
           now, to check in a few sessions whether the change helped. An
           edit may even flip the direction, so the arm comes from the
           value actually applied. */
        $arm = TipLearner::arm($key, $item['current_value'] ?? null, $value);
        $learner = app(TipLearner::class);
        $learner->recordFeedback($profile->child_id, $arm, $items[$idx]['status']);
        $learner->startOutcome($profile->child_id, $arm, $this->recentStats($profile));

        $this->logEvent('Insights', 'applySuggestion success', [
            'child_id'    => $childId,
            'setting_key' => $key,
            'value'       => $value,
            'status'      => $items[$idx]['status'],
        ]);
        return $this->successResponse('Suggestion applied',
            $this->serializeSuggestion($row));
    }

    // Mark one tip as dismissed without changing settings.
    public function dismissSuggestion(Request $request, string $childId): JsonResponse
    {
        $this->logEvent('Insights', 'dismissSuggestion called', [
            'child_id' => $childId,
            'item_id'  => $request->input('item_id'),
        ]);
        $profile = $this->ownedProfile($request, $childId);
        if (!$profile) {
            $this->logWarn('Insights', 'dismissSuggestion child not found', [
                'child_id' => $childId,
            ]);
            return $this->errorResponse('Child profile not found', 'NOT_FOUND', 404);
        }

        $validator = Validator::make($request->all(), [
            'item_id' => 'required|string',
        ]);
        if ($validator->fails()) {
            $this->logWarn('Insights', 'dismissSuggestion validation failed', [
                'errors' => $validator->errors()->all(),
            ]);
            return $this->errorResponse(
                'Validation failed: ' . implode(', ', $validator->errors()->all()),
                'VALIDATION_ERROR',
                422
            );
        }

        $row = AiSuggestion::where('child_id', $profile->child_id)->first();
        if (!$row) {
            $this->logWarn('Insights', 'dismissSuggestion no cached row', [
                'child_id' => $childId,
            ]);
            return $this->errorResponse('No suggestions to dismiss', 'NOT_FOUND', 404);
        }

        $items = $row->items;
        $idx = $this->findItemIndex($items, $request->input('item_id'));
        if ($idx === null) {
            $this->logWarn('Insights', 'dismissSuggestion item not found', [
                'item_id' => $request->input('item_id'),
            ]);
            return $this->errorResponse('Suggestion item not found', 'NOT_FOUND', 404);
        }
        $items[$idx]['status'] = 'dismissed';
        $row->items = $items;
        $row->save();

        // Learning: the caregiver said no to this kind of tip.
        $item = $items[$idx];
        $arm = $item['arm'] ?? TipLearner::arm(
            (string) $item['setting_key'], $item['current_value'] ?? null, $item['suggested_value'] ?? null);
        app(TipLearner::class)->recordFeedback($profile->child_id, $arm, 'dismissed');

        $this->logEvent('Insights', 'dismissSuggestion success', [
            'child_id' => $childId,
            'item_id'  => $items[$idx]['id'] ?? null,
        ]);
        return $this->successResponse('Suggestion dismissed',
            $this->serializeSuggestion($row));
    }

    private function findItemIndex(array $items, string $itemId): ?int
    {
        foreach ($items as $i => $item) {
            if (($item['id'] ?? null) === $itemId) {
                return $i;
            }
        }
        return null;
    }

    private function valuesEqual(mixed $a, mixed $b): bool
    {
        if (is_bool($a) || is_bool($b)) {
            return (bool) $a === (bool) $b;
        }
        if (is_numeric($a) && is_numeric($b)) {
            return abs((float) $a - (float) $b) < 0.005;
        }
        return (string) $a === (string) $b;
    }

    private function ownedProfile(Request $request, string $childId): ?ChildProfile
    {
        $caregiver = $request->get('auth_caregiver');
        return $caregiver
            ? $caregiver->childProfiles()->where('child_id', $childId)->first()
            : null;
    }

    // The child's listening numbers over the last 30 days.
    private function recentStats(ChildProfile $profile): array
    {
        $now = Carbon::now(self::TZ);
        $sessions = $profile->listeningHistory()
            ->where('created_at', '>=', $now->copy()->subDays(SettingsAdvisor::WINDOW_DAYS))
            ->get();
        return app(SettingsAdvisor::class)->summarize($sessions, $now);
    }

    private function serializeSuggestion(AiSuggestion $row): array
    {
        return [
            'suggestion_id' => $row->suggestion_id,
            'child_id'      => $row->child_id,
            'confidence'    => $row->confidence,
            'is_stale'      => (bool) $row->is_stale,
            'generated_at'  => $row->generated_at?->format('Y-m-d H:i:s'),
            'source_stats'  => $row->source_stats,
            'items'         => $row->items,
        ];
    }

    // Build the last 7 days (oldest first), each starting at 0 minutes.
    private function emptyWeek(Carbon $now): array
    {
        $week = [];
        for ($i = 6; $i >= 0; $i--) {
            $d = $now->copy()->subDays($i)->startOfDay();
            $week[$d->format('Y-m-d')] = [
                'date'    => $d->format('Y-m-d'),
                'day'     => $d->format('D'),
                'minutes' => 0,
            ];
        }
        return $week;
    }

    // Turn a timestamp into a Y-m-d key in the caregiver's timezone.
    private function dayKey($ts): string
    {
        return Carbon::parse($ts)->setTimezone(self::TZ)->format('Y-m-d');
    }

    // All the days the caregiver's children listened.
    private function collectDayKeys(array $childIds): array
    {
        if (empty($childIds)) {
            return [];
        }
        return ListeningHistory::query()
            ->whereIn('child_id', $childIds)
            ->orderByDesc('created_at')
            ->pluck('created_at')
            ->map(fn ($ts) => $this->dayKey($ts))
            ->unique()
            ->values()
            ->all();
    }

    /* Daily streak that shows how many days in a row up to today have a session.
       Counts from yesterday if today has none yet, so the streak isn't
       lost just because the child hasn't listened today. */
    private function computeStreak(array $distinctDayKeys, Carbon $now): int
    {
        if (empty($distinctDayKeys)) {
            return 0;
        }
        $set = array_flip($distinctDayKeys);
        $cursor = $now->copy()->startOfDay();
        // If today has none yet, start from yesterday.
        if (!isset($set[$cursor->format('Y-m-d')])) {
            $cursor->subDay();
        }
        $streak = 0;
        while (isset($set[$cursor->format('Y-m-d')])) {
            $streak++;
            $cursor->subDay();
        }
        return $streak;
    }

    // Top 5 audiobooks by total minutes across the caregiver's children.
    private function topStories(array $childIds): array
    {
        if (empty($childIds)) {
            return [];
        }
        return ListeningHistory::query()
            ->whereIn('listening_history.child_id', $childIds)
            ->leftJoin('audiobooks', 'listening_history.audiobook_id', '=', 'audiobooks.audiobook_id')
            ->selectRaw(
                'listening_history.audiobook_id as audiobook_id, '
                . 'MAX(audiobooks.title) as title, '
                . 'MAX(audiobooks.cover_image) as cover_image, '
                . 'SUM(duration_seconds) as secs, '
                . 'COUNT(*) as plays'
            )
            ->groupBy('listening_history.audiobook_id')
            ->orderByDesc('secs')
            ->limit(5)
            ->get()
            ->map(fn ($r) => [
                'audiobook_id' => $r->audiobook_id,
                'title'        => $r->title ?? 'Untitled',
                'cover_image'  => $this->mediaUrl($r->cover_image),
                'minutes'      => (int) round(((int) $r->secs) / 60),
                'plays'        => (int) $r->plays,
            ])
            ->toArray();
    }

    // The 10 most recent sessions across the caregiver's children.
    private function recentSessions(array $childIds): array
    {
        if (empty($childIds)) {
            return [];
        }
        return ListeningHistory::query()
            ->whereIn('listening_history.child_id', $childIds)
            ->leftJoin('audiobooks', 'listening_history.audiobook_id', '=', 'audiobooks.audiobook_id')
            ->leftJoin('child_profiles', 'listening_history.child_id', '=', 'child_profiles.child_id')
            ->orderByDesc('listening_history.created_at')
            ->limit(10)
            ->select([
                'listening_history.history_id as history_id',
                'listening_history.child_id as child_id',
                'listening_history.audiobook_id as audiobook_id',
                'listening_history.duration_seconds as duration_seconds',
                'listening_history.completed as completed',
                'listening_history.mood as mood',
                'listening_history.created_at as created_at',
                'audiobooks.title as audiobook_title',
                'audiobooks.cover_image as audiobook_cover',
                'child_profiles.name as child_name',
                'child_profiles.avatar_emoji as child_emoji',
                'child_profiles.avatar_color as child_color',
            ])
            ->get()
            ->map(fn ($r) => [
                'history_id'       => $r->history_id,
                'child_id'         => $r->child_id,
                'child_name'       => $r->child_name ?? '-',
                'child_emoji'      => $r->child_emoji ?? '🌟',
                'child_color'      => $r->child_color ?? '#F5D5DD',
                'audiobook_id'     => $r->audiobook_id,
                'audiobook_title'  => $r->audiobook_title ?? 'Untitled',
                'cover_image'      => $this->mediaUrl($r->audiobook_cover),
                'duration_minutes' => (int) round(((int) $r->duration_seconds) / 60),
                'completed'        => (bool) $r->completed,
                'mood'             => $r->mood,
                'at'               => Carbon::parse($r->created_at)
                    ->setTimezone(self::TZ)
                    ->format('Y-m-d H:i'),
            ])
            ->toArray();
    }

    /* Make a full URL from a stored path using the request's host (not
       APP_URL), so it works for emulator and real devices alike.
       Full URLs (Gemini images) are left as-is. */
    protected function mediaUrl(?string $path): ?string
    {
        if ($path === null || $path === '') {
            return null;
        }
        if (\Illuminate\Support\Str::startsWith($path, ['http://', 'https://'])) {
            return $path;
        }
        $base = rtrim(request()->getSchemeAndHttpHost(), '/');
        return $base . '/' . ltrim($path, '/');
    }

    // The mood with the most picks, or null if there are none.
    private function topMood(array $counts): ?string
    {
        arsort($counts);
        $top = array_key_first($counts);
        return ($top !== null && $counts[$top] > 0) ? $top : null;
    }
}
