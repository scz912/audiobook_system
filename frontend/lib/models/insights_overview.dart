import 'package:flutter/material.dart';

import '_json_helpers.dart';

class ChildInsight {
  final String childId;
  final String name;
  final String avatarEmoji;
  final String avatarColorHex;
  final String? favoriteGenre;
  final int listeningMinutes;
  final int sessions;
  final int completed;
  final int completionRate;
  final String? topMood;
  final double avgSessionMinutes;
  final int streakDays;

  const ChildInsight({
    required this.childId,
    required this.name,
    required this.avatarEmoji,
    required this.avatarColorHex,
    this.favoriteGenre,
    this.listeningMinutes = 0,
    this.sessions = 0,
    this.completed = 0,
    this.completionRate = 0,
    this.topMood,
    this.avgSessionMinutes = 0.0,
    this.streakDays = 0,
  });

  Color get avatarColor => _hexToColor(avatarColorHex);

  factory ChildInsight.fromJson(Map<String, dynamic> json) {
    return ChildInsight(
      childId: safeString(json['child_id']),
      name: safeString(json['name'], 'Child'),
      avatarEmoji: safeString(json['avatar_emoji'], '🌟'),
      avatarColorHex: safeString(json['avatar_color'], '#F5D5DD'),
      favoriteGenre: safeNullableString(json['favorite_genre']),
      listeningMinutes: safeInt(json['listening_minutes']) ?? 0,
      sessions: safeInt(json['sessions']) ?? 0,
      completed: safeInt(json['completed']) ?? 0,
      completionRate: safeInt(json['completion_rate']) ?? 0,
      topMood: safeNullableString(json['top_mood']),
      avgSessionMinutes: safeDouble(json['avg_session_minutes']) ?? 0.0,
      streakDays: safeInt(json['streak_days']) ?? 0,
    );
  }

  static Color _hexToColor(String hex) {
    var cleaned = hex.replaceAll('#', '');
    if (cleaned.length == 6) cleaned = 'FF$cleaned';
    final value = int.tryParse(cleaned, radix: 16) ?? 0xFFF5D5DD;
    return Color(value);
  }
}

// One day in the last-seven-days mini chart.
class DayMinutes {
  final String date; // YYYY-MM-DD (KL local)
  final String dayLabel; // short weekday name, e.g. "Mon"
  final int minutes;

  const DayMinutes({
    required this.date,
    required this.dayLabel,
    required this.minutes,
  });

  factory DayMinutes.fromJson(Map<String, dynamic> json) => DayMinutes(
        date: safeString(json['date']),
        dayLabel: safeString(json['day']),
        minutes: safeInt(json['minutes']) ?? 0,
      );
}

// One row in the "top stories" list.
class TopStory {
  final String audiobookId;
  final String title;
  final String? coverImage;
  final int minutes;
  final int plays;

  const TopStory({
    required this.audiobookId,
    required this.title,
    this.coverImage,
    this.minutes = 0,
    this.plays = 0,
  });

  factory TopStory.fromJson(Map<String, dynamic> json) => TopStory(
        audiobookId: safeString(json['audiobook_id']),
        title: safeString(json['title'], 'Untitled'),
        coverImage: safeNullableString(json['cover_image']),
        minutes: safeInt(json['minutes']) ?? 0,
        plays: safeInt(json['plays']) ?? 0,
      );
}

// One row in the recent activity feed.
class RecentSession {
  final String historyId;
  final String childId;
  final String childName;
  final String childEmoji;
  final String childColorHex;
  final String audiobookId;
  final String audiobookTitle;
  final String? coverImage;
  final int durationMinutes;
  final bool completed;
  final String? mood;

  // "YYYY-MM-DD HH:MM" in KL local time.
  final String at;

  const RecentSession({
    required this.historyId,
    required this.childId,
    required this.childName,
    required this.childEmoji,
    required this.childColorHex,
    required this.audiobookId,
    required this.audiobookTitle,
    this.coverImage,
    this.durationMinutes = 0,
    this.completed = false,
    this.mood,
    required this.at,
  });

  Color get childColor => ChildInsight._hexToColor(childColorHex);

  factory RecentSession.fromJson(Map<String, dynamic> json) => RecentSession(
        historyId: safeString(json['history_id']),
        childId: safeString(json['child_id']),
        childName: safeString(json['child_name'], '—'),
        childEmoji: safeString(json['child_emoji'], '🌟'),
        childColorHex: safeString(json['child_color'], '#F5D5DD'),
        audiobookId: safeString(json['audiobook_id']),
        audiobookTitle: safeString(json['audiobook_title'], 'Untitled'),
        coverImage: safeNullableString(json['cover_image']),
        durationMinutes: safeInt(json['duration_minutes']) ?? 0,
        completed: safeBool(json['completed']),
        mood: safeNullableString(json['mood']),
        at: safeString(json['at']),
      );
}

class InsightsOverview {
  final int totalChildren;
  final int totalListeningMinutes;
  final int totalSessions;
  final int completedSessions;
  final int completionRate;
  final String? topMood;
  final Map<String, int> moodBreakdown;
  final double avgSessionMinutes;
  final int streakDays;
  final List<DayMinutes> lastSevenDays;
  final List<TopStory> topStories;
  final List<RecentSession> recentSessions;
  final List<ChildInsight> children;

  const InsightsOverview({
    this.totalChildren = 0,
    this.totalListeningMinutes = 0,
    this.totalSessions = 0,
    this.completedSessions = 0,
    this.completionRate = 0,
    this.topMood,
    this.moodBreakdown = const {},
    this.avgSessionMinutes = 0.0,
    this.streakDays = 0,
    this.lastSevenDays = const [],
    this.topStories = const [],
    this.recentSessions = const [],
    this.children = const [],
  });

  factory InsightsOverview.empty() => const InsightsOverview();

  factory InsightsOverview.fromJson(Map<String, dynamic> json) {
    final rawMoods = json['mood_breakdown'];
    final moods = <String, int>{};
    if (rawMoods is Map) {
      rawMoods.forEach((key, value) {
        moods[key.toString()] = safeInt(value) ?? 0;
      });
    }
    List<T> listOf<T>(dynamic raw, T Function(Map<String, dynamic>) f) =>
        raw is List
            ? raw.whereType<Map<String, dynamic>>().map(f).toList()
            : <T>[];

    return InsightsOverview(
      totalChildren: safeInt(json['total_children']) ?? 0,
      totalListeningMinutes: safeInt(json['total_listening_minutes']) ?? 0,
      totalSessions: safeInt(json['total_sessions']) ?? 0,
      completedSessions: safeInt(json['completed_sessions']) ?? 0,
      completionRate: safeInt(json['completion_rate']) ?? 0,
      topMood: safeNullableString(json['top_mood']),
      moodBreakdown: moods,
      avgSessionMinutes: safeDouble(json['avg_session_minutes']) ?? 0.0,
      streakDays: safeInt(json['streak_days']) ?? 0,
      lastSevenDays: listOf(json['last_seven_days'], DayMinutes.fromJson),
      topStories: listOf(json['top_stories'], TopStory.fromJson),
      recentSessions: listOf(json['recent_sessions'], RecentSession.fromJson),
      children: listOf(json['children'], ChildInsight.fromJson),
    );
  }
}
