import 'package:flutter/material.dart';

import '../models/community/member.dart';
import '../services/database_service.dart';

// Friends, incoming requests, and member search results.
class FriendsState extends ChangeNotifier {
  List<Member> _friends = const [];
  List<Member> _pending = const [];
  List<Member> _searchResults = const [];
  bool _loading = false;
  bool _searching = false;
  String? _lastError;

  List<Member> get friends => List.unmodifiable(_friends);
  List<Member> get pending => List.unmodifiable(_pending);
  List<Member> get searchResults => List.unmodifiable(_searchResults);
  bool get loading => _loading;
  bool get searching => _searching;
  String? get lastError => _lastError;
  int get pendingCount => _pending.length;

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    final friendsResp = await DatabaseService.listFriends();
    final pendingResp = await DatabaseService.pendingRequests();
    if (friendsResp.success && friendsResp.data is List<Member>) {
      _friends = friendsResp.data as List<Member>;
    }
    if (pendingResp.success && pendingResp.data is List<Member>) {
      _pending = pendingResp.data as List<Member>;
    }
    _loading = false;
    notifyListeners();
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
    _searchResults = const [];
    _lastError = null;
    notifyListeners();
  }
}
