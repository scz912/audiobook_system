import '_json_helpers.dart';

// One suggested setting change (one item in `ai_suggestions.items`).
class AiSuggestionItem {
  final String id;

  /* One of: reading_speed, narrator_voice, volume, text_scale,
     auto_play_next, read_along. */
  final String settingKey;

  /* The child's current value, so the UI can show "now 1.00 → 0.90". */
  final dynamic currentValue;

  // The value Gemini suggested (numbers, booleans, or enum strings).
  final dynamic suggestedValue;

  /* The value saved when the caregiver accepted (maybe edited). Null while
     still pending. */
  final dynamic appliedValue;

  final String reason;

  // pending | accepted | edited | dismissed
  final String status;

  const AiSuggestionItem({
    required this.id,
    required this.settingKey,
    required this.suggestedValue,
    required this.reason,
    required this.status,
    this.currentValue,
    this.appliedValue,
  });

  factory AiSuggestionItem.fromJson(Map<String, dynamic> json) {
    return AiSuggestionItem(
      id: safeString(json['id']),
      settingKey: safeString(json['setting_key']),
      currentValue: json['current_value'],
      suggestedValue: json['suggested_value'],
      appliedValue: json['applied_value'],
      reason: safeString(json['reason']),
      status: safeString(json['status'], 'pending'),
    );
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted' || status == 'edited';
  bool get isDismissed => status == 'dismissed';
}

/* One row from `ai_suggestions` — the latest saved Gemini tips for a child. */
class AiSuggestion {
  final String? suggestionId;
  final String childId;

  /* 'low' when there were few sessions — the UI shows a "low confidence"
     hint then. */
  final String confidence;

  /* True when a fresh analysis failed and these are the old tips. The UI
     shows a "couldn't refresh" banner then. */
  final bool isStale;

  final DateTime? generatedAt;
  final Map<String, dynamic>? sourceStats;
  final List<AiSuggestionItem> items;

  const AiSuggestion({
    required this.childId,
    required this.confidence,
    required this.isStale,
    required this.items,
    this.suggestionId,
    this.generatedAt,
    this.sourceStats,
  });

  factory AiSuggestion.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = <AiSuggestionItem>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          items.add(AiSuggestionItem.fromJson(item));
        }
      }
    }
    final rawStats = json['source_stats'];
    return AiSuggestion(
      suggestionId: safeNullableString(json['suggestion_id']),
      childId: safeString(json['child_id']),
      confidence: safeString(json['confidence'], 'normal'),
      isStale: safeBool(json['is_stale']),
      generatedAt: safeDate(json['generated_at']),
      sourceStats: rawStats is Map<String, dynamic> ? rawStats : null,
      items: items,
    );
  }

  bool get isLowConfidence => confidence == 'low';
  bool get isEmpty => items.isEmpty;
  Iterable<AiSuggestionItem> get pending => items.where((i) => i.isPending);
}
