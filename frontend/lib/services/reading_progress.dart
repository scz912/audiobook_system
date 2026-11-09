import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/* Where a child stopped in a book they didn't finish, so the home page can
   offer "Continue reading". One per child, on this device: the most recent
   unfinished book. Finishing a book clears it. */
class ReadingProgress {
  const ReadingProgress({
    required this.audiobookId,
    required this.title,
    required this.page,
    required this.pageNumber,
    required this.totalPages,
    this.coverImage,
    this.audioPositionMs = 0,
    this.answers = const {},
  });

  final String audiobookId;
  final String title;
  final String? coverImage;
  // The page on screen when they left (0-based).
  final int page;
  // That page as the child sees it ("page 3 of 8").
  final int pageNumber;
  final int totalPages;
  // Books with a recording: where the recording was.
  final int audioPositionMs;
  // Interactive books: the answers picked so far, so the same path opens.
  final Map<int, int> answers;

  static String _key(String childId) => 'reading_progress_$childId';

  // Bumped after every save or clear, so the home page can refresh once the
  // player (which saves as it closes) is gone.
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static Future<ReadingProgress?> load(String childId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(childId));
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return ReadingProgress(
        audiobookId: j['audiobookId'] as String,
        title: j['title'] as String,
        coverImage: j['coverImage'] as String?,
        page: (j['page'] as num).toInt(),
        pageNumber: (j['pageNumber'] as num?)?.toInt() ?? (j['page'] as num).toInt() + 1,
        totalPages: (j['totalPages'] as num).toInt(),
        audioPositionMs: (j['audioPositionMs'] as num?)?.toInt() ?? 0,
        answers: {
          for (final e in ((j['answers'] as Map?) ?? const {}).entries)
            int.parse(e.key as String): (e.value as num).toInt(),
        },
      );
    } catch (_) {
      return null; // unreadable: treat as nothing saved
    }
  }

  static Future<void> save(String childId, ReadingProgress p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(childId),
      jsonEncode({
        'audiobookId': p.audiobookId,
        'title': p.title,
        'coverImage': p.coverImage,
        'page': p.page,
        'pageNumber': p.pageNumber,
        'totalPages': p.totalPages,
        'audioPositionMs': p.audioPositionMs,
        'answers': {for (final e in p.answers.entries) '${e.key}': e.value},
      }),
    );
    changed.value++;
  }

  // Clear it, but only if it's for [audiobookId] (when given), so finishing
  // one book doesn't wipe a different unfinished one.
  static Future<void> clear(String childId, {String? audiobookId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (audiobookId != null) {
      final saved = await load(childId);
      if (saved != null && saved.audiobookId != audiobookId) return;
    }
    await prefs.remove(_key(childId));
    changed.value++;
  }
}
