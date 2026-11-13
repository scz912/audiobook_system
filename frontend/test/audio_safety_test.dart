import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:autism_audiobook/audio/audio_safety.dart';
import 'package:autism_audiobook/pages/shared/guardian_pin_dialog.dart';
import 'package:autism_audiobook/state/language_state.dart';

void main() {
  group('AudioSafety (FR5, FR10, NFR5)', () {
    test('music is never louder than the ceiling', () {
      expect(AudioSafety.clampBgm(100), AudioSafety.bgmCeiling);
      expect(AudioSafety.clampBgm(AudioSafety.bgmCeiling + 1), AudioSafety.bgmCeiling);
      expect(AudioSafety.clampBgm(-5), 0);
      expect(AudioSafety.clampBgm(30), 30);
    });

    test('warns only above the level where music competes with the voice', () {
      expect(AudioSafety.bgmTooLoud(AudioSafety.bgmRecommended), isFalse);
      expect(AudioSafety.bgmTooLoud(AudioSafety.bgmWarnAbove), isFalse);
      expect(AudioSafety.bgmTooLoud(AudioSafety.bgmWarnAbove + 5), isTrue);
    });

    test('the recommended level is below the warning and the ceiling', () {
      expect(AudioSafety.bgmRecommended, lessThan(AudioSafety.bgmWarnAbove));
      expect(AudioSafety.bgmWarnAbove, lessThan(AudioSafety.bgmCeiling));
    });

    test('fades last at least 300 ms (NFR5)', () {
      expect(AudioSafety.fade.inMilliseconds, greaterThanOrEqualTo(300));
    });
  });

  testWidgets('entering Child Mode asks for the PIN with "Start" wording (FR16)',
      (tester) async {
    var entered = false;
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => LanguageState(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                entered = await showGuardianPinDialog(context,
                    entering: true, verifyPin: (pin) async => pin == '1234');
              },
              child: const Text('enter'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('enter'));
    await tester.pumpAndSettle();

    expect(find.text('Enter PIN to start Child Mode'), findsOneWidget);
    expect(find.text('Start Child\nMode'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.pumpAndSettle();
    expect(entered, isTrue);
  });
}
