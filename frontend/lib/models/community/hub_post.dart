import '../_json_helpers.dart';
import 'member.dart';

// A shared audiobook in the hub feed.
class HubPost {
  final String postId;
  final String? caption;
  final bool includeMusic;
  final DateTime? createdAt;
  final Member? author;

  final String audiobookId;
  final String bookTitle;
  final String? bookAuthor;
  final String? bookLanguage;
  final String? coverImage;

  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final bool isMine;

  const HubPost({
    required this.postId,
    this.caption,
    this.includeMusic = false,
    this.createdAt,
    this.author,
    required this.audiobookId,
    required this.bookTitle,
    this.bookAuthor,
    this.bookLanguage,
    this.coverImage,
    this.likeCount = 0,
    this.commentCount = 0,
    this.likedByMe = false,
    this.isMine = false,
  });

  factory HubPost.fromJson(Map<String, dynamic> json) {
    final book = json['audiobook'] as Map<String, dynamic>? ?? {};
    final author = json['author'];
    return HubPost(
      postId: safeString(json['post_id']),
      caption: safeNullableString(json['caption']),
      includeMusic: safeBool(json['include_music']),
      createdAt: safeDate(json['created_at']),
      author: author is Map<String, dynamic> ? Member.fromJson(author) : null,
      audiobookId: safeString(book['audiobook_id']),
      bookTitle: safeString(book['title'], 'Story'),
      bookAuthor: safeNullableString(book['author']),
      bookLanguage: safeNullableString(book['language']),
      coverImage: safeNullableString(book['cover_image']),
      likeCount: safeInt(json['like_count']) ?? 0,
      commentCount: safeInt(json['comment_count']) ?? 0,
      likedByMe: safeBool(json['liked_by_me']),
      isMine: safeBool(json['is_mine']),
    );
  }

  // A copy with the like toggled — lets the UI update before the server replies.
  HubPost copyWithLike({required bool liked, required int count}) {
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
      likeCount: count,
      commentCount: commentCount,
      likedByMe: liked,
      isMine: isMine,
    );
  }
}
