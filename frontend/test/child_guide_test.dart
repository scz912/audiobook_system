import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autism_audiobook/models/child_profile.dart';
import 'package:autism_audiobook/pages/child/child_shell.dart';
import 'package:autism_audiobook/state/language_state.dart';
import 'package:autism_audiobook/state/profiles_state.dart';
import 'package:autism_audiobook/state/settings_state.dart';
import 'package:autism_audiobook/widgets/guide.dart';

const _child = ChildProfile(
  childId: 'kid-1',
  name: 'Mia',
  age: 7,
  avatarEmoji: '🐱',
  avatarColorHex: '#F5D5DD',
);

Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LanguageState()),
      ChangeNotifierProvider(create: (_) => ProfilesState()..enterChildMode(_child)),
      ChangeNotifierProvider(create: (_) => SettingsState()),
    ],
    child: const MaterialApp(home: ChildShell()),
  ));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('first visit: the guide starts, and picking a mood moves it on', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpShell(tester);

    expect(find.text("Hi! I'm Paige!"), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('How do you feel? Tap one.'), findsOneWidget);

    // Learned by doing: tapping a mood is what moves the guide on.
    await tester.tap(find.text('Happy'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Your books! Tap one to listen.'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Skip'), findsNothing);
    expect(await GuideMemory.isDone('child.kid-1'), isTrue);
  });

  testWidgets('a child who has seen it is not shown it again', (tester) async {
    SharedPreferences.setMockInitialValues({'guide_done.child.kid-1': true});
    await _pumpShell(tester);
    expect(find.text("Hi! I'm Paige!"), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });
}
