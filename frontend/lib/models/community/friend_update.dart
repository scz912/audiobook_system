import '../_json_helpers.dart';
import 'member.dart';

// The answer to a friend request I sent: accepted or declined.
class FriendUpdate {
  final String friendshipId;
  final bool accepted;
  final Member person;

  const FriendUpdate({
    required this.friendshipId,
    required this.accepted,
    required this.person,
  });

  factory FriendUpdate.fromJson(Map<String, dynamic> json) {
    final person = json['person'];
    return FriendUpdate(
      friendshipId: safeString(json['friendship_id']),
      accepted: safeString(json['status']) == 'accepted',
      person: Member.fromJson(
          person is Map<String, dynamic> ? person : const <String, dynamic>{}),
    );
  }
}
