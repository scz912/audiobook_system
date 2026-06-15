import 'package:flutter/material.dart';

import '../models/child_profile.dart';
import '../services/database_service.dart';

class ProfilesState extends ChangeNotifier {
  List<ChildProfile> _profiles = const [];
  ChildProfile? _activeProfile;
  String? _currentMood;
  String? _ownerCaregiverId; // which caregiver the loaded profiles belong to
  bool _loading = false;
  String? _lastError;

  List<ChildProfile> get profiles => List.unmodifiable(_profiles);
  ChildProfile? get activeProfile => _activeProfile;

  /* The mood the child picked on the Home screen. Saved with the next
     listening session. */
  String? get currentMood => _currentMood;
  bool get loading => _loading;
  String? get lastError => _lastError;

  void setMood(String? mood) {
    _currentMood = mood;
    notifyListeners();
  }

  int get totalChildren => _profiles.length;
  int get totalListeningMinutes =>
      _profiles.fold(0, (sum, p) => sum + p.listeningMinutes);
  int get averageEngagement => _profiles.isEmpty ? 0 : 87;

  Future<void> refresh({String? caregiverId}) async {
    // Switching caregiver — clear the old list first.
    if (caregiverId != null && caregiverId != _ownerCaregiverId) {
      _profiles = const [];
      _activeProfile = null;
      _ownerCaregiverId = caregiverId;
      notifyListeners();
    }
    _loading = true;
    notifyListeners();
    final resp = await DatabaseService.listChildProfiles();
    if (resp.success && resp.data is List<ChildProfile>) {
      _profiles = resp.data as List<ChildProfile>;
      _lastError = null;
    } else {
      // Keep the old list on failure so a brief error doesn't wipe it.
      _lastError = resp.message;
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> addProfile({
    required String name,
    required int age,
    required String avatarEmoji,
    required String avatarColorHex,
    String? favoriteGenre,
  }) async {
    final resp = await DatabaseService.createChildProfile(
      name: name,
      age: age,
      avatarEmoji: avatarEmoji,
      avatarColorHex: avatarColorHex,
      favoriteGenre: favoriteGenre,
    );
    if (resp.success && resp.data is ChildProfile) {
      _profiles = [..._profiles, resp.data as ChildProfile];
      notifyListeners();
      return true;
    }
    _lastError = resp.message;
    notifyListeners();
    return false;
  }

  /* Update a child's fields. Only the ones you pass are sent. */
  Future<bool> updateProfile(
    String childId, {
    String? name,
    int? age,
    String? avatarEmoji,
    String? avatarColorHex,
    String? favoriteGenre,
  }) async {
    final patch = <String, dynamic>{
      'name': ?name,
      'age': ?age,
      'avatar_emoji': ?avatarEmoji,
      'avatar_color': ?avatarColorHex,
      'favorite_genre': ?favoriteGenre,
    };
    if (patch.isEmpty) return true;
    final resp = await DatabaseService.updateChildProfile(childId, patch);
    if (resp.success && resp.data is Map<String, dynamic>) {
      final updated = ChildProfile.fromJson(resp.data as Map<String, dynamic>);
      _profiles = [
        for (final p in _profiles) p.childId == childId ? updated : p,
      ];
      if (_activeProfile?.childId == childId) _activeProfile = updated;
      _lastError = null;
      notifyListeners();
      return true;
    }
    _lastError = resp.message;
    notifyListeners();
    return false;
  }

  Future<bool> deleteProfile(String childId) async {
    final resp = await DatabaseService.deleteChildProfile(childId);
    if (resp.success) {
      _profiles = _profiles.where((p) => p.childId != childId).toList();
      if (_activeProfile?.childId == childId) _activeProfile = null;
      notifyListeners();
      return true;
    }
    _lastError = resp.message;
    notifyListeners();
    return false;
  }

  void enterChildMode(ChildProfile profile) {
    _activeProfile = profile;
    _currentMood = null; // fresh session
    notifyListeners();
  }

  void exitChildMode() {
    _activeProfile = null;
    _currentMood = null;
    notifyListeners();
  }

  void clear() {
    _profiles = const [];
    _activeProfile = null;
    _currentMood = null;
    _ownerCaregiverId = null;
    notifyListeners();
  }
}
