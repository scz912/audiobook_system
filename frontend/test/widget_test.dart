import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autism_audiobook/main.dart';

void main() {
  testWidgets('app builds without crashing', (WidgetTester tester) async {
    // Just verify the widget tree can be built. AuthState.bootstrap() touches
    // SharedPreferences which the test binding doesn't fully mock, so we
    // tolerate any post-frame async work.
    await tester.pumpWidget(const AudiobookApp());
    // Let Paige's loading-screen hello finish so no timer is left pending.
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
