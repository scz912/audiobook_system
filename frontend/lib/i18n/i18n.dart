import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../state/language_state.dart';

// Extension on BuildContext to easily access localized strings from LanguageState.
extension I18nContext on BuildContext {
  // Use in widget build methods (subscribes to changes).
  String tr(String key) => watch<LanguageState>().tr(key);

  // Use in callbacks or places where you don't want to subscribe to changes.
  String trRead(String key) => read<LanguageState>().tr(key);
}
