import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autism_audiobook/widgets/adaptive_row.dart';
import 'package:autism_audiobook/widgets/marquee_text.dart';
import 'package:autism_audiobook/widgets/shelf_nav_bar.dart';

Widget _host(double width, Widget child, {double textScale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

Widget _card() => AdaptiveRow(
  leading: const SizedBox(key: Key('lead'), width: 56, height: 56),
  body: const Text('Tony\nAge 9 • Fantasy\n19 min listened', key: Key('body')),
  trailing: Wrap(
    key: const Key('trail'),
    spacing: 8,
    children: [
      TextButton(onPressed: () {}, child: const Text('Enter')),
      const SizedBox(width: 80, height: 36),
    ],
  ),
);

void main() {
  testWidgets('wide: buttons sit beside the text', (tester) async {
    await tester.pumpWidget(_host(500, _card()));
    final body = tester.getRect(find.byKey(const Key('body')));
    final trail = tester.getRect(find.byKey(const Key('trail')));
    expect(trail.left, greaterThan(body.right));
    expect(trail.top, lessThan(body.bottom));
    expect(body.width, greaterThanOrEqualTo(140));
  });

  testWidgets('narrow: buttons drop under the text, which keeps the width', (tester) async {
    await tester.pumpWidget(_host(300, _card()));
    final body = tester.getRect(find.byKey(const Key('body')));
    final trail = tester.getRect(find.byKey(const Key('trail')));
    expect(trail.top, greaterThanOrEqualTo(body.bottom));
    expect(body.width, 300 - 56 - 14);
    expect(trail.right, 300);
    expect(tester.takeException(), isNull);
  });

  testWidgets('big text stacks sooner', (tester) async {
    await tester.pumpWidget(_host(420, _card()));
    final wide = tester.getRect(find.byKey(const Key('trail')));
    expect(wide.top, lessThan(tester.getRect(find.byKey(const Key('body'))).bottom));
    await tester.pumpWidget(_host(420, _card(), textScale: 2));
    final body = tester.getRect(find.byKey(const Key('body')));
    expect(tester.getRect(find.byKey(const Key('trail'))).top, greaterThanOrEqualTo(body.bottom));
  });

  testWidgets('buttons still tap after stacking', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(260, AdaptiveRow(
      body: const Text('A long name here'),
      trailing: TextButton(onPressed: () => taps++, child: const Text('Enter')),
    )));
    await tester.tap(find.text('Enter'));
    expect(taps, 1);
  });

  testWidgets('marquee: short text sits still', (tester) async {
    await tester.pumpWidget(_host(300, const MarqueeText('Short')));
    expect(find.text('Short'), findsOneWidget);
    expect(find.descendant(of: find.byType(MarqueeText), matching: find.byType(Transform)), findsNothing);
  });

  testWidgets('marquee: long text rests, then scrolls left and loops', (tester) async {
    const title = 'Rahsia di Sebalik Kulit Ungu Puteri Manggis Yang Tebal';
    await tester.pumpWidget(_host(200, const MarqueeText(title, velocity: 100, pause: Duration(seconds: 1), gap: 50)));
    await tester.pump();
    expect(find.text(title), findsNWidgets(2));
    double dx() => tester.widget<Transform>(find.descendant(of: find.byType(MarqueeText), matching: find.byType(Transform)).first).transform.getTranslation().x;
    await tester.pump(const Duration(milliseconds: 500));
    expect(dx(), 0);
    await tester.pump(const Duration(milliseconds: 1000)); // 0.5s into the move
    expect(dx(), closeTo(-50, 2));
    // Width of one loop = text + gap; after a full loop it is back at rest.
    final textW = tester.getSize(find.text(title).first).width;
    final loopMs = 1000 + (textW + 50) / 100 * 1000;
    await tester.pump(Duration(milliseconds: (loopMs - 1500 + 200).round()));
    expect(dx(), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('marquee: still with reduced motion', (tester) async {
    const title = 'Rahsia di Sebalik Kulit Ungu Puteri Manggis Yang Tebal';
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: const Scaffold(body: SizedBox(width: 200, child: MarqueeText(title))),
      ),
    ));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(title), findsOneWidget);
    expect(find.descendant(of: find.byType(MarqueeText), matching: find.byType(Transform)), findsNothing);
  });
  testWidgets('two lines: a title that fits sits still', (tester) async {
    await tester.pumpWidget(_host(300, const MarqueeText('Dogs and Cats', maxLines: 2)));
    expect(find.text('Dogs and Cats'), findsOneWidget);
    expect(find.descendant(of: find.byType(MarqueeText), matching: find.byType(Transform)), findsNothing);
  });

  testWidgets('two lines: a 3-line title scrolls up, rests 1.5s at the end, loops', (tester) async {
    const title = 'Rahsia di Sebalik Kulit Manggis dan Kawan-kawannya di Hutan Durian Yang Besar';
    const style = TextStyle(fontSize: 15, height: 1.2);
    await tester.pumpWidget(_host(150, const MarqueeText(title,
        maxLines: 2, style: style, velocity: 20, pause: Duration(seconds: 1))));
    await tester.pump();
    final window = tester.getSize(find.byType(MarqueeText));
    final full = tester.getSize(find.text(title));
    expect(full.height, greaterThan(window.height)); // 3+ lines in a 2-line box
    final travel = full.height - window.height;
    double dy() => tester.widget<Transform>(find.descendant(
        of: find.byType(MarqueeText), matching: find.byType(Transform))).transform.getTranslation().y;
    await tester.pump(const Duration(milliseconds: 900));
    expect(dy(), 0); // resting at the top
    final moveMs = travel / 20 * 1000;
    await tester.pump(Duration(milliseconds: (100 + moveMs + 200).round()));
    expect(dy(), closeTo(-travel, 0.01)); // reached the end, resting
    await tester.pump(const Duration(milliseconds: 1000));
    expect(dy(), closeTo(-travel, 0.01)); // still resting (1.5s in all)
    await tester.pump(const Duration(milliseconds: 400));
    expect(dy(), 0); // back at the top for the next loop
    expect(tester.takeException(), isNull);
  });

  for (final cups in [false, true]) {
    testWidgets('shelf: spheres clear a 48dp button bar (cups: $cups)', (tester) async {
      const screen = Size(360, 760);
      const navBar = 48.0;
      final keys = List.generate(7, (_) => GlobalKey());
      Widget bar(bool rotate) => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: screen,
            padding: EdgeInsets.only(bottom: navBar),
            // No bobbing, and the cups appear at once.
            disableAnimations: true,
          ),
          child: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: ShelfNavBar(
              items: [
                for (var i = 0; i < 7; i++)
                  ShelfNavItem(icon: Icons.star, label: 'Tab $i', color: Colors.pink),
              ],
              currentIndex: 5,
              onTap: (_) {},
              rotateItems: rotate,
              sphereKeys: keys,
            ),
          ),
        ),
      );
      await tester.binding.setSurfaceSize(screen);
      await tester.pumpWidget(bar(false));
      if (cups) {
        await tester.pumpWidget(bar(true));
        await tester.pump();
      }
      for (final k in keys) {
        final r = tester.getRect(find.byKey(k));
        // A cup's base sits 1.525 radii + 4.5 below its sphere's centre
        // (see _BowlPainter.depthBelowCenter; tilted cups reach less far).
        final lowest = cups ? r.center.dy + 1.525 * r.width / 2 + 4.5 : r.bottom;
        expect(lowest, lessThanOrEqualTo(screen.height - navBar + 0.5),
            reason: 'sphere at $r');
      }
      await tester.binding.setSurfaceSize(null);
    });
  }
}
