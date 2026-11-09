import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autism_audiobook/pages/onboarding/welcome_page.dart';
import 'package:autism_audiobook/state/auth_state.dart';
import 'package:autism_audiobook/state/language_state.dart';

Widget _app({VoidCallback? onLogin}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageState()),
        ChangeNotifierProvider(create: (_) => AuthState()),
      ],
      child: MaterialApp(home: WelcomePage(onLogin: onLogin)),
    );

Future<void> _settle(WidgetTester tester) => tester.pump(const Duration(milliseconds: 600));

// Small screens scroll, so bring the target into view first.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [320.0, 412.0]) {
    testWidgets('hi -> language -> about -> who -> account at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app());
      await _settle(tester);

      expect(find.text("I'm Paige!"), findsOneWidget);
      await tester.tap(find.text('Next'));
      await _settle(tester);
      expect(find.text('Pick a language'), findsOneWidget);

      // Picking Bahasa Melayu switches the app's language right away.
      await _tap(tester, find.text('Bahasa Malaysia'));
      expect(find.text('Pilih bahasa'), findsOneWidget);
      await _tap(tester, find.text('English'));

      await tester.tap(find.text('Next'));
      await _settle(tester);
      expect(find.text('Calm stories, made for you'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await _settle(tester);

      expect(find.text('Who is using the app?'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(await WelcomePage.seen(), isTrue);

      await _tap(tester, find.text('I use it on my own'));
      expect(find.text('Make your account'), findsOneWidget);
      // A teenager on their own is asked their age.
      expect(find.text('How old are you?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Skip jumps to "who"; a parent account asks no age', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await _settle(tester);

    await tester.tap(find.text('Skip'));
    await _settle(tester);
    expect(find.text('Who is using the app?'), findsOneWidget);

    await _tap(tester, find.text('A parent helps me'));
    expect(find.text('Make a parent account'), findsOneWidget);
    expect(find.text('How old are you?'), findsNothing);

    // Back returns to the choice.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await _settle(tester);
    expect(find.text('Who is using the app?'), findsOneWidget);
  });

  testWidgets('"Sign in" goes to the login page', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var login = false;
    await tester.pumpWidget(_app(onLogin: () => login = true));
    await _settle(tester);
    await tester.tap(find.text('Skip'));
    await _settle(tester);
    // "Sign in" is the end of "Already have an account? Sign in".
    await _tap(tester, find.textContaining('Sign in'));
    expect(login, isTrue);
  });
}
