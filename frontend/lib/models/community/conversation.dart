import '../_json_helpers.dart';
import 'contact_settings.dart';
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
  // One-to-one chats: my settings for the other person. Null for groups.
  final ContactSettings? contact;

  const Conversation({
    required this.conversationId,
    required this.type,
    required this.title,
    this.participants = const [],
    this.lastMessageBody,
    this.lastMessageSenderId,
    this.lastActivity,
    this.unreadCount = 0,
    this.contact,
  });

  bool get isGroup => type == 'group';
  bool get isMuted => contact?.isMuted ?? false;
  bool get isFavorite => contact?.isFavorite ?? false;
  bool get isBlocked => contact?.isBlocked ?? false;

  // The other person in a one-to-one chat.
  String? get otherId =>
      !isGroup && participants.isNotEmpty ? participants.first.caregiverId : null;

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
      contact: ContactSettings.fromJson(json['contact']),
    );
  }
}
