import '../_json_helpers.dart';
import 'shared_book.dart';

// One message in a chat thread, including its sender's name and avatar.
class ChatMessage {
  final String messageId;
  final String conversationId;
  final String senderId;
  final String body; // may be empty when the message only shares a book
  final bool isMine;
  final DateTime? sentAt;
  final SharedBook? book;

  final String senderName;
  final String senderEmoji;
  final String senderColor;

  const ChatMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.isMine,
    this.sentAt,
    this.book,
    this.senderName = 'Family',
    this.senderEmoji = '🙂',
    this.senderColor = '#DCE4FF',
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'];
    final s = sender is Map<String, dynamic> ? sender : const {};
    return ChatMessage(
      messageId: safeString(json['message_id']),
      conversationId: safeString(json['conversation_id']),
      senderId: safeString(json['sender_id']),
      body: safeString(json['body']),
      isMine: safeBool(json['is_mine']),
      sentAt: safeDate(json['sent_at']),
      book: SharedBook.fromJson(json['audiobook']),
      senderName: safeString(s['name'], 'Family'),
      senderEmoji: safeString(s['avatar_emoji'], '🙂'),
      senderColor: safeString(s['avatar_color'], '#DCE4FF'),
    );
  }

  // The same message with its shared book marked as saved.
  ChatMessage withBookSaved() => ChatMessage(
        messageId: messageId,
        conversationId: conversationId,
        senderId: senderId,
        body: body,
        isMine: isMine,
        sentAt: sentAt,
        book: book?.copyWith(inMyLibrary: true),
        senderName: senderName,
        senderEmoji: senderEmoji,
        senderColor: senderColor,
      );
}
