import 'package:flutter/material.dart';

import '../models/community/hub_post.dart';
import '../services/api_service.dart';
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
    final current = _latest(post);
    final willLike = !current.likedByMe;
    final newCount = current.likeCount + (willLike ? 1 : -1);
    _replace(post.postId, current.copyWithLike(liked: willLike, count: newCount));
    notifyListeners();

    final resp = willLike
        ? await DatabaseService.likePost(post.postId)
        : await DatabaseService.unlikePost(post.postId);
    if (resp.success && resp.data is Map<String, dynamic>) {
      final data = resp.data as Map<String, dynamic>;
      final count = data['like_count'] is int ? data['like_count'] as int : newCount;
      _replace(post.postId,
          _latest(post).copyWithLike(liked: data['liked'] == true, count: count));
    } else {
      _replace(post.postId, current);
    }
    notifyListeners();
  }

  /* Leave [emoji] as my one reaction. Tapping the emoji I already left
     takes it off; another emoji moves my reaction there, so I'm never
     counted twice. Likes aren't touched. The card updates right away, then
     the server's totals replace the guess (or it goes back on failure). */
  Future<void> react(HubPost post, String emoji) async {
    final current = _latest(post);
    final removing = current.myReaction == emoji;
    _replace(post.postId, current.copyWithMyReaction(removing ? null : emoji));
    notifyListeners();

    final resp = removing
        ? await DatabaseService.removePostReaction(post.postId)
        : await DatabaseService.reactToPost(post.postId, emoji);
    if (resp.success && resp.data is Map<String, dynamic>) {
      _replace(post.postId,
          _latest(post).copyWithReactionSummary(resp.data as Map<String, dynamic>));
    } else {
      // Didn't go through: put the card back as it was.
      _replace(post.postId, current);
    }
    notifyListeners();
  }

  /* Save the post's book into my library. Every post sharing that book
     then shows it as saved. */
  Future<ApiResponse> saveBook(HubPost post) async {
    final resp = await DatabaseService.saveAudiobookCopy(post.audiobookId!);
    if (resp.success) {
      _feed = [
        for (final p in _feed)
          p.audiobookId == post.audiobookId ? p.copyWithBookSaved() : p,
      ];
      notifyListeners();
    }
    return resp;
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

  // The feed's current copy of [post] (it may have changed since a tap).
  HubPost _latest(HubPost post) =>
      _feed.firstWhere((p) => p.postId == post.postId, orElse: () => post);

  void _replace(String postId, HubPost updated) {
    _feed = [for (final p in _feed) p.postId == postId ? updated : p];
  }

  void clear() {
    _feed = const [];
    _lastError = null;
    notifyListeners();
  }
}
