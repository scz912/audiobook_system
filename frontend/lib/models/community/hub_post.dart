import '../_json_helpers.dart';
import 'member.dart';

// How many people reacted to a post with one emoji.
class ReactionCount {
  final String emoji;
  final int count;
  const ReactionCount(this.emoji, this.count);
}

// A shared audiobook in the hub feed.
class HubPost {
  /* The emoji people can react with. The heart isn't one: it's the like
     button, which is separate. */
  static const reactionEmoji = ['👍', '😂', '😮', '😢', '🎉', '🙏', '🥰', '👏'];

  final String postId;
  final String? caption;
  final bool includeMusic;
  final DateTime? createdAt;
  final Member? author;

  // Null on text-only posts.
  final String? audiobookId;
  final String? bookTitle;
  final String? bookAuthor;
  final String? bookLanguage;
  final String? coverImage;
  // I made the book or already saved a copy of it.
  final bool bookInMyLibrary;

  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final bool isMine;
  // My emoji reaction (at most one), and everyone's, most used first.
  final String? myReaction;
  final List<ReactionCount> reactions;

  const HubPost({
    required this.postId,
    this.caption,
    this.includeMusic = false,
    this.createdAt,
    this.author,
    this.audiobookId,
    this.bookTitle,
    this.bookAuthor,
    this.bookLanguage,
    this.coverImage,
    this.bookInMyLibrary = false,
    this.likeCount = 0,
    this.commentCount = 0,
    this.likedByMe = false,
    this.isMine = false,
    this.myReaction,
    this.reactions = const [],
  });

  // Whether this post shares an audiobook (vs. text only).
  bool get hasBook => audiobookId != null && audiobookId!.isNotEmpty;

  static List<ReactionCount> parseReactions(dynamic json) {
    if (json is! List) return const [];
    return [
      for (final r in json.whereType<Map<String, dynamic>>())
        if (safeNullableString(r['emoji']) != null && (safeInt(r['count']) ?? 0) > 0)
          ReactionCount(safeString(r['emoji']), safeInt(r['count'])!),
    ];
  }

  factory HubPost.fromJson(Map<String, dynamic> json) {
    final book = json['audiobook'] as Map<String, dynamic>?;
    final author = json['author'];
    return HubPost(
      postId: safeString(json['post_id']),
      caption: safeNullableString(json['caption']),
      includeMusic: safeBool(json['include_music']),
      createdAt: safeDate(json['created_at']),
      author: author is Map<String, dynamic> ? Member.fromJson(author) : null,
      audiobookId: book == null ? null : safeNullableString(book['audiobook_id']),
      bookTitle: book == null ? null : safeString(book['title'], 'Story'),
      bookAuthor: book == null ? null : safeNullableString(book['author']),
      bookLanguage: book == null ? null : safeNullableString(book['language']),
      coverImage: book == null ? null : safeNullableString(book['cover_image']),
      bookInMyLibrary: book != null && safeBool(book['in_my_library']),
      likeCount: safeInt(json['like_count']) ?? 0,
      commentCount: safeInt(json['comment_count']) ?? 0,
      likedByMe: safeBool(json['liked_by_me']),
      isMine: safeBool(json['is_mine']),
      myReaction: safeNullableString(json['my_reaction']),
      reactions: parseReactions(json['reactions']),
    );
  }

  HubPost _copy({
    bool? bookInMyLibrary,
    int? likeCount,
    bool? likedByMe,
    String? Function()? myReaction,
    List<ReactionCount>? reactions,
  }) {
    return HubPost(
      postId: postId,
      caption: caption,
      includeMusic: includeMusic,
      createdAt: createdAt,
      author: author,
      audiobookId: audiobookId,
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      bookLanguage: bookLanguage,
      coverImage: coverImage,
      bookInMyLibrary: bookInMyLibrary ?? this.bookInMyLibrary,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount,
      likedByMe: likedByMe ?? this.likedByMe,
      isMine: isMine,
      myReaction: myReaction != null ? myReaction() : this.myReaction,
      reactions: reactions ?? this.reactions,
    );
  }

  // A copy with the like toggled - lets the UI update before the server replies.
  HubPost copyWithLike({required bool liked, required int count}) =>
      _copy(likedByMe: liked, likeCount: count);

  /* A copy with my one reaction set to [emoji] (null takes it off). My old
     emoji loses my count and the new one gains it, so I'm only ever
     counted once. Likes aren't touched. */
  HubPost copyWithMyReaction(String? emoji) {
    final counts = {for (final r in reactions) r.emoji: r.count};
    final old = myReaction;
    if (old != null) {
      counts[old] = (counts[old] ?? 1) - 1;
      if (counts[old]! <= 0) counts.remove(old);
    }
    if (emoji != null) counts[emoji] = (counts[emoji] ?? 0) + 1;
    final list = [for (final e in counts.entries) ReactionCount(e.key, e.value)]
      ..sort((a, b) => b.count.compareTo(a.count));
    return _copy(myReaction: () => emoji, reactions: list);
  }

  // A copy with the server's reaction totals (from a react/unreact reply).
  HubPost copyWithReactionSummary(Map<String, dynamic> data) => _copy(
        myReaction: () => safeNullableString(data['my_reaction']),
        reactions: parseReactions(data['reactions']),
      );

  // A copy with the shared book marked as saved to my library.
  HubPost copyWithBookSaved() => _copy(bookInMyLibrary: true);
}
