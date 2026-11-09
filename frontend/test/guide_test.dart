import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autism_audiobook/state/language_state.dart';
import 'package:autism_audiobook/widgets/guide.dart';
import 'package:autism_audiobook/widgets/shelf_nav_bar.dart';

GuideController _controller(List<int> opened, List<String> log) => GuideController(
      openTab: opened.add,
      onFinish: () => log.add('finished'),
      steps: const [
        GuideStep('guide.ch_hi', tab: 0),
        GuideStep('guide.ch_tap_note', tab: 2, waitFor: GuideEvent.notePlayed),
        GuideStep('guide.ch_yay', celebrate: true),
      ],
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('GuideController', () {
    test('opens each step\'s tab and finishes after the last', () {
      final opened = <int>[];
      final log = <String>[];
      final g = _controller(opened, log)..start();
      expect(g.index, 0);
      g.next();
      expect(opened, [0, 2]);
      g.next();
      expect(g.isLast, isTrue);
      g.next();
      expect(g.active, isFalse);
      expect(log, ['finished']);
    });

    test('a waiting step moves on only for its own event', () {
      final g = _controller([], [])..start();
      g.report(GuideEvent.notePlayed); // step 0 isn't waiting
      expect(g.index, 0);
      g.next();
      g.report(GuideEvent.recordingStarted);
      expect(g.index, 1);
      g.report(GuideEvent.notePlayed);
      expect(g.index, 2);
    });

    test('skip ends the guide at once', () {
      final log = <String>[];
      final g = _controller([], log)..start();
      g.finish();
      expect(g.active, isFalse);
      expect(log, ['finished']);
    });

    test('remembers a finished guide per key', () async {
      expect(await GuideMemory.isDone('child.a'), isFalse);
      await GuideMemory.markDone('child.a');
      expect(await GuideMemory.isDone('child.a'), isTrue);
      expect(await GuideMemory.isDone('child.b'), isFalse);
    });
  });

  for (final width in [320.0, 412.0]) {
    testWidgets('overlay: Paige, Next and Skip work at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final log = <String>[];
      final g = _controller([], log)..start();

      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => LanguageState(),
        child: MaterialApp(
          home: Stack(children: [
            const Scaffold(body: Center(child: Text('page'))),
            ListenableBuilder(
              listenable: g,
              builder: (context, _) => g.active
                  ? GuideOverlay(
                      controller: g,
                      tabRect: (_) => const Rect.fromLTWH(20, 700, 48, 48),
                    )
                  : const SizedBox.shrink(),
            ),
          ]),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.text("Hi! I'm Paige!"), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Tap a key!'), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Tap a key!'), findsNothing);
      expect(log, ['finished']);
      // The page underneath is still there.
      expect(find.text('page'), findsOneWidget);
    });
  }

  testWidgets('taskbar shows icons only; names stay for screen readers', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shelf = GlobalKey<ShelfTabScaffoldState>();
    await tester.pumpWidget(MaterialApp(
      home: ShelfTabScaffold(
        key: shelf,
        body: const SizedBox.expand(),
        currentIndex: 0,
        onTap: (_) {},
        items: const [
          ShelfNavItem(icon: Icons.home_outlined, label: 'Home', color: Colors.blue),
          ShelfNavItem(icon: Icons.piano_outlined, label: 'Piano', color: Colors.pink),
        ],
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Home'), findsNothing);
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    // The guide can find each sphere.
    final rect = shelf.currentState!.sphereRect(1)!;
    expect(rect.center.dx, greaterThan(180));
    expect(rect.center.dy, greaterThan(600));
  });
}
