import 'package:flutter/material.dart';

import '../models/community/conversation.dart';
import '../services/database_service.dart';

// The list of chat threads. Individual threads manage their own messages.
class ChatState extends ChangeNotifier {
  List<Conversation> _conversations = const [];
  bool _loading = false;

  List<Conversation> get conversations => List.unmodifiable(_conversations);
  bool get loading => _loading;
  int get totalUnread =>
      _conversations.fold(0, (sum, c) => sum + c.unreadCount);

  // Unread messages that should light the red dot: muted chats don't.
  bool get hasUnmutedUnread =>
      _conversations.any((c) => c.unreadCount > 0 && !c.isMuted);

  /* Reload quietly for the red dot (no loading spinner). Fails silently -
     e.g. before the caregiver joins the community. */
  Future<void> refreshQuietly() async {
    final resp = await DatabaseService.listConversations();
    if (resp.success && resp.data is List<Conversation>) {
      _conversations = resp.data as List<Conversation>;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    final resp = await DatabaseService.listConversations();
    if (resp.success && resp.data is List<Conversation>) {
      _conversations = resp.data as List<Conversation>;
    }
    _loading = false;
    notifyListeners();
  }

  void clear() {
    _conversations = const [];
    notifyListeners();
  }
}
