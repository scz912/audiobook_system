import 'dart:math' as math;

import '../models/content_item.dart';
import 'music_genres.dart';

/// A listening genre and its share of the person's recent plays (0-1).
typedef GenreShare = ({String genre, double share});

/// A recommended audiobook, with why it was picked.
class Recommendation {
  final ContentItem book;
  final double score;
  // The listening genre that led to it (null if the mood alone did).
  final String? becauseGenre;
  // The background music's emotion tags that fit the mood.
  final List<String> moodTags;
  const Recommendation({
    required this.book,
    required this.score,
    required this.becauseGenre,
    required this.moodTags,
  });
}

/* Picks audiobooks whose background music suits what the person listens
   to and how they feel today. No AI: every audiobook's background track
   carries a genre and emotion tags, and those are scored against

   - taste: for each of the person's top listening genres, its share of
     their plays times how well the track's genre suits it (genreAffinity),
     added up, 0 to 1;
   - mood: today's mood (happy, calm, curious, sleepy) is a set of emotion
     words; the share of three of them the track carries, less a penalty
     for a word that clashes (an energetic track on a sleepy day), 0 to 1.

   score = 0.6 x taste + 0.4 x mood, or taste alone when no mood was picked
   today. Books that score 0, have no background music, or are still being
   made are left out; ties go to the better mood fit, then the title. */
class AudiobookRecommender {
  static const tasteWeight = 0.6;
  static const moodWeight = 0.4;

  static const moodEmotions = <String, Set<String>>{
    'happy': {'Happy', 'Playful', 'Upbeat', 'Energetic', 'Whimsical'},
    'calm': {'Calm', 'Peaceful', 'Gentle', 'Soothing', 'Relaxing'},
    'curious': {'Curious', 'Mysterious', 'Imaginative', 'Adventurous', 'Whimsical'},
    'sleepy': {'Calm', 'Soothing', 'Relaxing', 'Peaceful', 'Gentle'},
  };

  // Emotions that work against a mood.
  static const moodClashes = <String, Set<String>>{
    'calm': {'Energetic', 'Upbeat'},
    'sleepy': {'Energetic', 'Upbeat', 'Adventurous'},
    'happy': {},
    'curious': {},
  };

  /// Taste fit of a background genre, 0 to 1, and the listening genre
  /// that contributes most to it.
  static ({double score, String? because}) tasteFit(
      String? trackGenre, List<GenreShare> top) {
    if (trackGenre == null || top.isEmpty) return (score: 0, because: null);
    var sum = 0.0;
    String? because;
    var best = 0.0;
    for (final g in top) {
      final part = g.share * (genreAffinity[g.genre]?[trackGenre] ?? 0);
      sum += part;
      if (part > best) {
        best = part;
        because = g.genre;
      }
    }
    return (score: math.min(sum, 1.0), because: because);
  }

  /// Mood fit of a track's emotion tags, 0 to 1, and the tags that fit.
  static ({double score, List<String> tags}) moodFit(List<String> tags, String? mood) {
    final wanted = moodEmotions[mood];
    if (wanted == null) return (score: 0, tags: const []);
    final fits = tags.where(wanted.contains).toList();
    final clashes = tags.where((t) => moodClashes[mood]!.contains(t)).length;
    final score = (math.min(fits.length, 3) / 3 - 0.34 * clashes).clamp(0.0, 1.0);
    return (score: score.toDouble(), tags: fits);
  }

  /// Top listening genres from per-genre play counts: the [limit] most
  /// played, each with its share of those.
  /* The [limit] most played genres, as shares of their plays together.
     Others (songs of unknown genre) never takes a place: it says nothing
     about taste. [withOthers] adds it after them, for showing on the card. */
  static List<GenreShare> topGenres(Map<String, int> counts, {int limit = 3, bool withOthers = false}) {
    final sorted = counts.entries.where((e) => e.value > 0 && e.key != otherGenre).toList()
      ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    final top = sorted.take(limit).toList();
    final others = counts[otherGenre] ?? 0;
    if (withOthers && others > 0) top.add(MapEntry(otherGenre, others));
    final total = top.fold<int>(0, (s, e) => s + e.value);
    return [for (final e in top) (genre: e.key, share: e.value / total)];
  }

  static List<Recommendation> recommend(
    List<ContentItem> books,
    List<GenreShare> top,
    String? mood, {
    int limit = 3,
  }) {
    final hasMood = moodEmotions.containsKey(mood);
    final picks = <Recommendation>[];
    for (final b in books) {
      final track = b.musicTrack;
      if (track == null || b.status == 'processing') continue;
      final taste = tasteFit(track.genre, top);
      final fit = moodFit(track.tags, mood);
      final score = hasMood ? tasteWeight * taste.score + moodWeight * fit.score : taste.score;
      if (score <= 0) continue;
      picks.add(Recommendation(
        book: b,
        score: score,
        becauseGenre: taste.because,
        moodTags: fit.tags,
      ));
    }
    picks.sort((x, y) {
      final byScore = y.score.compareTo(x.score);
      if (byScore != 0) return byScore;
      final byMood = y.moodTags.length.compareTo(x.moodTags.length);
      return byMood != 0 ? byMood : x.book.title.compareTo(y.book.title);
    });
    return picks.take(limit).toList();
  }
}
