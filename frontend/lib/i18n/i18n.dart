import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../state/language_state.dart';

// Adds context.tr('key') for translated text.
extension I18nContext on BuildContext {
  // Use in build() — rebuilds when the language changes.
  String tr(String key) => watch<LanguageState>().tr(key);

  // Use in callbacks — doesn't rebuild.
  String trRead(String key) => read<LanguageState>().tr(key);
}
