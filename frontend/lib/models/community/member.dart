import '../_json_helpers.dart';

// A community member — used for people in search, friends, and post/comment authors.
class Member {
  final String caregiverId;
  final String name;
  final String? bio;
  final String avatarEmoji;
  final String avatarColor;

  /* This viewer's relationship to the member:
     none / friends / request_sent / request_received / blocked. */
  final String relation;
  final String? friendshipId;
  final int sharedCount;

  const Member({
    required this.caregiverId,
    required this.name,
    this.bio,
    this.avatarEmoji = '🙂',
    this.avatarColor = '#DCE4FF',
    this.relation = 'none',
    this.friendshipId,
    this.sharedCount = 0,
  });

  factory Member.fromJson(Map<String, dynamic> json) {
    return Member(
      caregiverId: safeString(json['caregiver_id']),
      name: safeString(json['name'], 'Family'),
      bio: safeNullableString(json['bio']),
      avatarEmoji: safeString(json['avatar_emoji'], '🙂'),
      avatarColor: safeString(json['avatar_color'], '#DCE4FF'),
      relation: safeString(json['relation'], 'none'),
      friendshipId: safeNullableString(json['friendship_id']),
      sharedCount: safeInt(json['shared_count']) ?? 0,
    );
  }
}
