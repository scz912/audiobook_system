import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:autism_audiobook/pages/shared/guardian_pin_dialog.dart';
import 'package:autism_audiobook/state/language_state.dart';

/* The child-mode exit flow in miniature: a page opens the PIN dialog and, on
   success, replaces itself with the caregiver page - like ChildShell does.
   A black screen means the navigator was left with no page at all. */
Widget _app(Future<bool> Function(String) verifyPin) {
  return ChangeNotifierProvider(
    create: (_) => LanguageState(),
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final ok =
                    await showGuardianPinDialog(context, verifyPin: verifyPin);
                if (!ok || !context.mounted) return;
                Navigator.of(context).pushReplacement(MaterialPageRoute(
                  builder: (_) => const Scaffold(body: Text('caregiver home')),
                ));
              },
              child: const Text('exit'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('typing the PIN and tapping Exit does not leave a black screen',
      (tester) async {
    // A short delay, like the network: both checks are in flight together.
    await tester.pumpWidget(_app((_) =>
        Future.delayed(const Duration(milliseconds: 50), () => true)));
    await tester.tap(find.text('exit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1234'); // auto-submits
    await tester.tap(find.text('Exit Child\nMode')); // ...and again by hand
    await tester.pump(const Duration(milliseconds: 50)); // first answer
    await tester.pump(const Duration(milliseconds: 10)); // second answer
    await tester.pumpAndSettle();

    expect(find.text('caregiver home'), findsOneWidget);
  });

  testWidgets('back while the PIN is checking does not leave a black screen',
      (tester) async {
    await tester.pumpWidget(_app((_) =>
        Future.delayed(const Duration(milliseconds: 100), () => true)));
    await tester.tap(find.text('exit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1234');
    await tester.pump(const Duration(milliseconds: 20));
    // System back closes the dialog while the check is still running.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 90)); // check returns
    await tester.pumpAndSettle();

    // The caregiver cancelled, so they stay where they were.
    expect(find.text('exit'), findsOneWidget);
  });

  testWidgets('a wrong PIN keeps the dialog open', (tester) async {
    await tester.pumpWidget(_app((_) async => false));
    await tester.tap(find.text('exit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '9999');
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('caregiver home'), findsNothing);
  });
}
