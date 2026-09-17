import '../_json_helpers.dart';
import 'member.dart';

// One comment on a hub post.
class HubComment {
  final String commentId;
  final String body;
  final DateTime? createdAt;
  final Member? author;
  final bool isMine;

  const HubComment({
    required this.commentId,
    required this.body,
    this.createdAt,
    this.author,
    this.isMine = false,
  });

  factory HubComment.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    return HubComment(
      commentId: safeString(json['comment_id']),
      body: safeString(json['body']),
      createdAt: safeDate(json['created_at']),
      author: author is Map<String, dynamic> ? Member.fromJson(author) : null,
      isMine: safeBool(json['is_mine']),
    );
  }
}
