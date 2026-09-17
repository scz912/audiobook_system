import 'package:flutter/material.dart';

import '../models/community/community_invite.dart';
import '../models/community/member.dart';
import '../services/database_service.dart';

/* Tracks whether the caregiver has joined the private community, plus the
   invite codes they've created. Gates the whole community area. */
class CommunityState extends ChangeNotifier {
  bool _isMember = false;
  bool _loading = false;
  bool _checked = false;
  String? _lastError;
  Member? _me;
  List<CommunityInvite> _invites = const [];

  bool get isMember => _isMember;
  bool get loading => _loading;
  bool get checked => _checked;
  String? get lastError => _lastError;
  Member? get me => _me;
  List<CommunityInvite> get invites => List.unmodifiable(_invites);

  Future<void> refreshStatus() async {
    _loading = true;
    notifyListeners();
    final resp = await DatabaseService.communityStatus();
    if (resp.success && resp.data is Map<String, dynamic>) {
      final data = resp.data as Map<String, dynamic>;
      _isMember = data['is_member'] == true;
      final profile = data['profile'];
      _me = profile is Map<String, dynamic> ? Member.fromJson(profile) : null;
      _lastError = null;
    } else {
      _lastError = resp.message;
    }
    _loading = false;
    _checked = true;
    notifyListeners();
  }

  Future<bool> join() async {
    final resp = await DatabaseService.joinCommunity();
    if (resp.success) {
      _isMember = true;
      notifyListeners();
      return true;
    }
    _lastError = resp.message;
    notifyListeners();
    return false;
  }

  Future<bool> acceptInvite(String code) async {
    final resp = await DatabaseService.acceptInvite(code);
    if (resp.success) {
      _isMember = true;
      notifyListeners();
      return true;
    }
    _lastError = resp.message;
    notifyListeners();
    return false;
  }

  Future<void> loadInvites() async {
    final resp = await DatabaseService.myInvites();
    if (resp.success && resp.data is List<CommunityInvite>) {
      _invites = resp.data as List<CommunityInvite>;
      notifyListeners();
    }
  }

  Future<CommunityInvite?> createInvite({String? email}) async {
    final resp = await DatabaseService.createInvite(email: email);
    if (resp.success && resp.data is CommunityInvite) {
      final invite = resp.data as CommunityInvite;
      _invites = [invite, ..._invites];
      notifyListeners();
      return invite;
    }
    _lastError = resp.message;
    notifyListeners();
    return null;
  }

  // Clear on sign-out so the next caregiver starts fresh.
  void clear() {
    _isMember = false;
    _checked = false;
    _me = null;
    _invites = const [];
    _lastError = null;
    notifyListeners();
  }
}
