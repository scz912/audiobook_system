import 'package:flutter/material.dart';

import '../models/community/hub_post.dart';
import '../services/database_service.dart';

// The shared-audiobook feed.
class HubState extends ChangeNotifier {
  List<HubPost> _feed = const [];
  bool _loading = false;
  String? _lastError;

  List<HubPost> get feed => List.unmodifiable(_feed);
  bool get loading => _loading;
  String? get lastError => _lastError;

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    final resp = await DatabaseService.hubFeed();
    if (resp.success && resp.data is List<HubPost>) {
      _feed = resp.data as List<HubPost>;
      _lastError = null;
    } else {
      _lastError = resp.message;
    }
    _loading = false;
    notifyListeners();
  }

  // Flip a like, updating the card right away then confirming with the server.
  Future<void> toggleLike(HubPost post) async {
    final willLike = !post.likedByMe;
    final newCount = post.likeCount + (willLike ? 1 : -1);
    _replace(post.postId, post.copyWithLike(liked: willLike, count: newCount));
    notifyListeners();

    final resp = willLike
        ? await DatabaseService.likePost(post.postId)
        : await DatabaseService.unlikePost(post.postId);
    if (resp.success && resp.data is Map<String, dynamic>) {
      final data = resp.data as Map<String, dynamic>;
      final count = data['like_count'] is int ? data['like_count'] as int : newCount;
      final liked = data['liked'] == true;
      _replace(post.postId, post.copyWithLike(liked: liked, count: count));
      notifyListeners();
    }
  }

  Future<bool> removePost(String postId) async {
    final resp = await DatabaseService.deleteHubPost(postId);
    if (resp.success) {
      _feed = _feed.where((p) => p.postId != postId).toList();
      notifyListeners();
      return true;
    }
    return false;
  }

  void _replace(String postId, HubPost updated) {
    _feed = [for (final p in _feed) p.postId == postId ? updated : p];
  }

  void clear() {
    _feed = const [];
    _lastError = null;
    notifyListeners();
  }
}
