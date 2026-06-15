import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/app_strings.dart';

/* Holds the currently-selected app language and persists it across launches.
   Wired into MultiProvider in main.dart and consumed via `context.tr(...)`. */
class LanguageState extends ChangeNotifier {
  static const _prefsKey = 'app_language';

  String _code = 'en';
  bool _loaded = false;

  // Current language code ('en' or 'ms').
  String get code => _code;
  bool get loaded => _loaded;

  // Translate a key under the current language.
  String tr(String key) => AppStrings.get(key, _code);

  // Load the saved language at app start. Falls back to English.
  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored != null && AppStrings.supportedCodes.contains(stored)) {
      _code = stored;
    }
    _loaded = true;
    notifyListeners();
  }

  // Switch the app language. Persists immediately.
  Future<void> setLanguage(String code) async {
    if (!AppStrings.supportedCodes.contains(code) || code == _code) return;
    _code = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, code);
    notifyListeners();
  }
}
