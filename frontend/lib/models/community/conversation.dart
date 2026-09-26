import '../_json_helpers.dart';
import 'member.dart';

// A chat thread in the list - direct or group, with its last message and unread count.
class Conversation {
  final String conversationId;
  final String type; // direct | group
  final String title;
  final List<Member> participants;
  final String? lastMessageBody;
  final String? lastMessageSenderId;
  final DateTime? lastActivity;
  final int unreadCount;

  const Conversation({
    required this.conversationId,
    required this.type,
    required this.title,
    this.participants = const [],
    this.lastMessageBody,
    this.lastMessageSenderId,
    this.lastActivity,
    this.unreadCount = 0,
  });

  bool get isGroup => type == 'group';

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final last = json['last_message'];
    return Conversation(
      conversationId: safeString(json['conversation_id']),
      type: safeString(json['type'], 'direct'),
      title: safeString(json['title'], 'Chat'),
      participants: (json['participants'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Member.fromJson)
          .toList(),
      lastMessageBody: last is Map ? safeNullableString(last['body']) : null,
      lastMessageSenderId:
          last is Map ? safeNullableString(last['sender_id']) : null,
      lastActivity: safeDate(json['last_activity']),
      unreadCount: safeInt(json['unread_count']) ?? 0,
    );
  }
}
