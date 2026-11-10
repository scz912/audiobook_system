import 'package:flutter/material.dart';

import '../models/community/friend_update.dart';
import '../models/community/member.dart';
import '../services/database_service.dart';

/* Friends, incoming requests, answers to my requests, and member search
   results. Incoming requests and unseen answers put a red dot on the
   Community and Friends tabs. */
class FriendsState extends ChangeNotifier {
  List<Member> _friends = const [];
  List<Member> _pending = const [];
  // Answers not yet seen (they cause the dot), and ones already seen this
  // session (still listed in the Friends tab).
  List<FriendUpdate> _unseenUpdates = const [];
  List<FriendUpdate> _seenUpdates = const [];
  List<Member> _searchResults = const [];
  // Every other member, for the "add friends" list.
  List<Member> _everyone = const [];
  bool _loading = false;
  bool _searching = false;
  String? _lastError;

  List<Member> get friends => List.unmodifiable(_friends);
  List<Member> get pending => List.unmodifiable(_pending);
  List<Member> get searchResults => List.unmodifiable(_searchResults);
  // Members who aren't friends yet, to send a request to.
  List<Member> get notFriends =>
      _everyone.where((m) => m.relation != 'friends').toList();
  bool get loading => _loading;
  bool get searching => _searching;
  String? get lastError => _lastError;
  int get pendingCount => _pending.length;
  List<FriendUpdate> get updates => [..._unseenUpdates, ..._seenUpdates];
  bool get hasUnseenUpdates => _unseenUpdates.isNotEmpty;
  bool get hasNotification => _pending.isNotEmpty || _unseenUpdates.isNotEmpty;

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    final friendsResp = await DatabaseService.listFriends();
    if (friendsResp.success && friendsResp.data is List<Member>) {
      _friends = friendsResp.data as List<Member>;
    }
    await _loadEveryone();
    await _loadNotifications();
    _loading = false;
    notifyListeners();
  }

  // Just what drives the red dot. Cheap enough to poll.
  Future<void> refreshNotifications() async {
    await _loadNotifications();
    notifyListeners();
  }

  Future<void> _loadNotifications() async {
    final pendingResp = await DatabaseService.pendingRequests();
    final updatesResp = await DatabaseService.friendRequestUpdates();
    if (pendingResp.success && pendingResp.data is List<Member>) {
      _pending = pendingResp.data as List<Member>;
    }
    if (updatesResp.success && updatesResp.data is List<FriendUpdate>) {
      // Skip ones already shown, in case "seen" hasn't reached the server.
      final seen = _seenUpdates.map((u) => u.friendshipId).toSet();
      _unseenUpdates = (updatesResp.data as List<FriendUpdate>)
          .where((u) => !seen.contains(u.friendshipId))
          .toList();
    }
  }

  // The Friends tab is showing the answers, so the dot can go.
  Future<void> markUpdatesSeen() async {
    if (_unseenUpdates.isEmpty) return;
    _seenUpdates = [..._unseenUpdates, ..._seenUpdates];
    _unseenUpdates = const [];
    notifyListeners();
    await DatabaseService.markFriendUpdatesSeen();
  }

  Future<void> _loadEveryone() async {
    final resp = await DatabaseService.searchMembers('');
    if (resp.success && resp.data is List<Member>) {
      _everyone = resp.data as List<Member>;
    }
  }

  Future<void> search(String term) async {
    _searching = true;
    notifyListeners();
    final resp = await DatabaseService.searchMembers(term);
    _searchResults =
        resp.success && resp.data is List<Member> ? resp.data as List<Member> : const [];
    _searching = false;
    notifyListeners();
  }

  void clearSearch() {
    _searchResults = const [];
    notifyListeners();
  }

  Future<bool> sendRequest(String caregiverId) async {
    final resp = await DatabaseService.sendFriendRequest(caregiverId);
    if (resp.success) {
      await search(''); // refresh relation labels in the current results
      await _loadEveryone();
      notifyListeners();
      return true;
    }
    _lastError = resp.message;
    notifyListeners();
    return false;
  }

  Future<bool> respond(String friendshipId, bool accept) async {
    final resp = await DatabaseService.respondFriendRequest(friendshipId, accept);
    if (resp.success) {
      await refresh();
      return true;
    }
    _lastError = resp.message;
    notifyListeners();
    return false;
  }

  Future<bool> removeFriend(String caregiverId) async {
    final resp = await DatabaseService.removeFriend(caregiverId);
    if (resp.success) {
      await refresh();
      return true;
    }
    _lastError = resp.message;
    notifyListeners();
    return false;
  }

  void clear() {
    _friends = const [];
    _pending = const [];
    _unseenUpdates = const [];
    _seenUpdates = const [];
    _searchResults = const [];
    _everyone = const [];
    _lastError = null;
    notifyListeners();
  }
}
