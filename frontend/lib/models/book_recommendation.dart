/* One audiobook picked for a child by the server's recommender
   (BookRecommender), with why. */
class BookRecommendation {
  final String audiobookId;
  final double score;
  // like_book | others_liked | fits_mood | music_taste | just_right | popular
  final String reasonCode;
  final Map<String, String> reasonParams;
  // Never listened to by this child.
  final bool isNew;

  const BookRecommendation({
    required this.audiobookId,
    required this.score,
    required this.reasonCode,
    this.reasonParams = const {},
    this.isNew = false,
  });

  factory BookRecommendation.fromJson(Map<String, dynamic> json) {
    final reason = json['reason'] is Map ? json['reason'] as Map : const {};
    final params = reason['params'] is Map ? reason['params'] as Map : const {};
    return BookRecommendation(
      audiobookId: '${json['audiobook_id'] ?? ''}',
      score: json['score'] is num ? (json['score'] as num).toDouble() : 0,
      reasonCode: '${reason['code'] ?? 'popular'}',
      reasonParams: {
        for (final e in params.entries)
          if (e.value != null) '${e.key}': '${e.value}',
      },
      isNew: json['new'] == true,
    );
  }
}
