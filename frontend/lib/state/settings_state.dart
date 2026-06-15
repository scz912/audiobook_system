import 'package:flutter/material.dart';

import '../models/user_settings.dart';
import '../services/database_service.dart';

/* Holds the settings for ONE child at a time — the child being configured
   (settings page) or the one in Child Mode (player). Call [loadForChild]
   when switching child. */
class SettingsState extends ChangeNotifier {
  UserSettings _settings = const UserSettings();
  String? _childId; // the child these settings belong to
  bool _loaded = false;
  bool _loading = false;
  String? _lastError;

  UserSettings get settings => _settings;
  String? get childId => _childId;
  NarratorVoice get voice => _settings.narratorVoice;
  double get readingSpeed => _settings.readingSpeed;
  double get volume => _settings.volume;
  double get textScale => _settings.textScale;
  bool get reducedAnimations => _settings.reducedAnimations;
  bool get autoPlayNext => _settings.autoPlayNext;
  bool get readAlong => _settings.readAlong;
  bool get loaded => _loaded;
  bool get loading => _loading;
  String? get lastError => _lastError;

  /* Load a child's settings. Shows defaults while loading so the UI never
     shows another child's values. */
  Future<void> loadForChild(String childId) async {
    _childId = childId;
    _settings = const UserSettings();
    _loaded = false;
    _loading = true;
    notifyListeners();

    final resp = await DatabaseService.getChildSettings(childId);
    // Ignore the reply if the child changed while loading.
    if (_childId != childId) return;
    if (resp.success && resp.data is UserSettings) {
      _settings = resp.data as UserSettings;
      _lastError = null;
    } else {
      _lastError = resp.message;
    }
    _loaded = true;
    _loading = false;
    notifyListeners();
  }

  Future<void> _patch(UserSettings updated) async {
    final childId = _childId;
    if (childId == null) return; // no child selected yet
    final previous = _settings;
    _settings = updated;
    notifyListeners();
    final resp = await DatabaseService.updateChildSettings(childId, updated);
    if (_childId != childId) return; // child switched while saving
    if (!resp.success) {
      _settings = previous;
      _lastError = resp.message;
      notifyListeners();
    } else if (resp.data is UserSettings) {
      _settings = resp.data as UserSettings;
      notifyListeners();
    }
  }

  Future<void> setVoice(NarratorVoice v) =>
      _patch(_settings.copyWith(narratorVoice: v));

  Future<void> setReadingSpeed(double v) =>
      _patch(_settings.copyWith(readingSpeed: v));

  Future<void> setVolume(double v) =>
      _patch(_settings.copyWith(volume: v));

  Future<void> setTextScale(double v) =>
      _patch(_settings.copyWith(textScale: v));

  Future<void> setReducedAnimations(bool v) =>
      _patch(_settings.copyWith(reducedAnimations: v));

  Future<void> setAutoPlayNext(bool v) =>
      _patch(_settings.copyWith(autoPlayNext: v));

  Future<void> setReadAlong(bool v) =>
      _patch(_settings.copyWith(readAlong: v));

  Future<bool> changePin({required String currentPin, required String newPin}) async {
    final resp = await DatabaseService.changePin(
      currentPin: currentPin,
      newPin: newPin,
    );
    if (!resp.success) {
      _lastError = resp.message;
      notifyListeners();
    }
    return resp.success;
  }

  void clear() {
    _settings = const UserSettings();
    _childId = null;
    _loaded = false;
    _loading = false;
    notifyListeners();
  }
}
