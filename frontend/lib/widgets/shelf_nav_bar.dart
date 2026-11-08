import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'notification_dot.dart';

class ShelfNavItem {
  final IconData icon;
  final String label;
  final Color color;
  // Shows a red notification dot on the sphere.
  final bool dot;

  const ShelfNavItem({
    required this.icon,
    required this.label,
    required this.color,
    this.dot = false,
  });
}

/* The app's taskbar: a curved shelf with each tab as a glossy sphere
   resting along its top edge. The open tab's sphere is 25% bigger and bobs
   gently up and down (one full bob every 2 seconds), with its name shown
   under it.

   In horizontal mode (the sideways piano page, or the phone turned to
   landscape) the shelf sinks away and each sphere is held in its own cup
   on a stick instead, fanned out along the curve. [rotateItems] turns the
   icons a quarter clockwise, for the sideways piano page. Both changes
   are animated. */
class ShelfNavBar extends StatefulWidget {
  final List<ShelfNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool rotateItems;
  // Colour the shelf is dyed with (the open tab's colour).
  final Color? dye;
  // One per tab, so [ShelfTabScaffold] can find where each sphere is.
  final List<GlobalKey>? slotKeys;

  const ShelfNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.rotateItems = false,
    this.dye,
    this.slotKeys,
  });

  @override
  State<ShelfNavBar> createState() => _ShelfNavBarState();
}

class _ShelfNavBarState extends State<ShelfNavBar> with TickerProviderStateMixin {
  // How far the open tab's sphere drifts up and down.
  static const _bobAmplitude = 5.0;
  static const _focusScale = 1.25;
  // How far a sphere's centre sits above the shelf's top edge, as a share
  // of its size - so the edge crosses its lower part.
  static const _perch = 0.2;
  // How much lower the middle of the shelf is than its ends.
  static const _sag = 12.0;
  static const _labelHeight = 15.0;
  static const _sidePadding = 8.0;
  // Tilt of the outermost holders in horizontal mode, in radians.
  static const _fan = 0.55;
  // Space between a sphere and the inside of its bowl.
  static const _bowlGap = 3.0;

  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  // 0 = shelf, 1 = cups on sticks.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  bool? _holders;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMorph();
  }

  @override
  void didUpdateWidget(covariant ShelfNavBar old) {
    super.didUpdateWidget(old);
    _syncMorph();
  }

  // Shelf or cups, following horizontal mode.
  void _syncMorph() {
    final holders =
        widget.rotateItems || MediaQuery.orientationOf(context) == Orientation.landscape;
    if (holders == _holders) return;
    final first = _holders == null;
    _holders = holders;
    if (first || MediaQuery.of(context).disableAnimations) {
      _morph.value = holders ? 1 : 0;
    } else {
      _morph.animateTo(holders ? 1 : 0, curve: Curves.easeInOutCubic);
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length;
    final still = MediaQuery.of(context).disableAnimations;
    final dye = widget.dye ?? AppColors.primaryBlue;

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final slot = (width - _sidePadding * 2) / n;
        final d = math.min(slot * 0.7, 48.0);
        final big = d * _focusScale;
        // Shelf top at its ends: room above for an enlarged, bobbing sphere.
        final shelfTopEnd = big * (0.5 + _perch) + _bobAmplitude + 4;
        // The shelf runs down to the bottom edge of the screen, under the
        // gesture bar too.
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        // Room below a closed sphere, down to the screen's edge: kept to
        // 60% of what the label and gesture bar would take, so the spheres
        // sit low (the label may run into the gesture bar's space).
        final belowSphere = 0.6 * ((big - d) * (0.5 - _perch) + _labelHeight + 4 + bottomInset);
        final height = shelfTopEnd + _sag + d * (0.5 - _perch) + belowSphere;

        // Shelf top at x: a gentle curve, lowest in the middle.
        double shelfTopAt(double x) {
          final u = (x - width / 2) / (width / 2);
          return shelfTopEnd + _sag * (1 - u * u);
        }

        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _morph,
                  builder: (context, _) => CustomPaint(
                    painter: _ShelfPainter(
                      topEnd: shelfTopEnd,
                      sag: _sag,
                      dye: dye,
                      sunk: _morph.value,
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < n; i++)
                () {
                  final x = _sidePadding + slot * (i + 0.5);
                  final item = widget.items[i];
                  final selected = i == widget.currentIndex;
                  return Positioned(
                    key: widget.slotKeys?[i],
                    left: x - slot / 2,
                    top: 0,
                    width: slot,
                    height: height,
                    child: Semantics(
                      button: true,
                      selected: selected,
                      label: item.label,
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onTap(i),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: selected ? 1 : 0),
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutBack,
                          builder: (context, focus, _) => AnimatedBuilder(
                            animation: Listenable.merge([_bob, _morph]),
                            builder: (context, _) {
                              final bob = still || focus <= 0
                                  ? 0.0
                                  : -math.sin(2 * math.pi * _bob.value) *
                                        _bobAmplitude *
                                        focus.clamp(0.0, 1.0);
                              return _buildSlot(
                                item: item,
                                d: d,
                                slot: slot,
                                shelfTop: shelfTopAt(x),
                                barHeight: height,
                                tilt: _fan * (x - width / 2) / (width / 2),
                                focus: focus,
                                bob: bob,
                                dye: dye,
                                showLabel: selected && !widget.rotateItems,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                }(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSlot({
    required ShelfNavItem item,
    required double d,
    required double slot,
    required double shelfTop,
    required double barHeight,
    required double tilt,
    required double focus,
    required double bob,
    required Color dye,
    required bool showLabel,
  }) {
    final scale = 1 + (_focusScale - 1) * focus;
    final size = d * scale;
    final m = Curves.easeInOut.transform(_morph.value);

    // On the shelf: perched on its top edge.
    final onShelf = Offset(slot / 2, shelfTop - size * _perch);

    /* In a holder: the bowl's base point is fixed (worked out from the
       closed-tab sphere size), so the bowl and stick never move; a bigger,
       open-tab sphere just sits higher in its bowl. */
    final down = Offset(math.sin(tilt), math.cos(tilt));
    final base =
        Offset(slot / 2, shelfTop - d * _perch) +
        down * _BowlPainter.depthBelowCenter(d / 2, _bowlGap);
    final restCenter = base - down * _BowlPainter.depthBelowCenter(size / 2, _bowlGap);

    final center = Offset.lerp(onShelf, restCenter, m)! + Offset(0, bob);

    _BowlPainter bowl(bool front) => _BowlPainter(
      front: front,
      base: base,
      radius: size / 2,
      gap: _bowlGap,
      bottom: barHeight,
      tilt: tilt,
      grown: _morph.value,
      dye: dye,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The bowl's inside and the stick, behind the sphere.
        if (_morph.value > 0)
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: bowl(false))),
          ),
        Positioned(
          top: center.dy - size / 2,
          left: center.dx - size / 2,
          width: size,
          height: size,
          child: _NavSphere(
            item: item,
            focus: focus.clamp(0.0, 1.0),
            rotateIcon: widget.rotateItems,
          ),
        ),
        // The dish's front wall (it sits below the sphere, never over it).
        if (_morph.value > 0)
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: bowl(true))),
          ),
        if (showLabel)
          Positioned(
            top: center.dy + size / 2 + 1,
            left: -6,
            right: -6,
            height: _labelHeight,
            // Fades out in horizontal mode, where the holder sits there.
            child: Opacity(
              opacity: focus.clamp(0.0, 1.0) * (1 - m),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/* One tab's sphere, lit from the top left. Closed tabs are a soft pearl
   tinted with the tab's colour; the open tab is in its full colour. The
   icon turns (animated) when [rotateIcon] changes. */
class _NavSphere extends StatelessWidget {
  final ShelfNavItem item;
  // 0 = closed tab, 1 = open tab.
  final double focus;
  final bool rotateIcon;

  const _NavSphere({required this.item, required this.focus, required this.rotateIcon});

  @override
  Widget build(BuildContext context) {
    final c = item.color;
    final base = Color.lerp(Color.lerp(Colors.white, c, 0.45), c, focus)!;
    final shade = Color.lerp(c, AppColors.textPrimary, 0.12 + 0.18 * focus)!;

    return LayoutBuilder(
      builder: (context, box) {
        final size = box.maxWidth;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.35, -0.45),
                    radius: 1.05,
                    colors: [Colors.white, base, shade],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                  boxShadow: [
                    if (focus > 0)
                      BoxShadow(
                        color: c.withValues(alpha: 0.55 * focus),
                        blurRadius: 14 * focus,
                      ),
                  ],
                ),
              ),
            ),
            // Glossy reflection.
            Positioned(
              top: size * 0.1,
              left: size * 0.22,
              width: size * 0.34,
              height: size * 0.18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.elliptical(size * 0.17, size * 0.09)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.85),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: AnimatedRotation(
                turns: rotateIcon ? 0.25 : 0,
                duration: const Duration(milliseconds: 550),
                curve: Curves.easeInOutBack,
                child: Icon(item.icon, size: size * 0.46, color: AppColors.textPrimary),
              ),
            ),
            if (item.dot)
              Positioned(top: size * 0.06, right: size * 0.06, child: const NotificationDot()),
          ],
        );
      },
    );
  }
}

/* Horizontal mode's holder for one sphere: a shallow dish (a quarter of
   a hollow sphere) seen a little from above, so its opening is an ellipse.
   The sphere floats just above the opening, never covered or touched by
   it. It is painted in two layers: [front] false paints the stick and the
   dish's inside (partly behind the sphere); true paints the dish's front
   wall. The stick runs from the dish's base to the bottom edge of the
   screen. Dish and stick lean away from the curve's centre (outer ones
   tilt outwards, like a fan). [grown] runs 0-1 as the dish swells out of
   its base and the stick pushes out. */
class _BowlPainter extends CustomPainter {
  final bool front;
  // Bottom of the bowl, where the stick starts.
  final Offset base;
  // Radius of the sphere being held.
  final double radius;
  final double gap;
  // The screen's bottom edge, in this painter's coordinates.
  final double bottom;
  // Lean from straight down, in radians (negative = left).
  final double tilt;
  final double grown;
  final Color dye;

  _BowlPainter({
    required this.front,
    required this.base,
    required this.radius,
    required this.gap,
    required this.bottom,
    required this.tilt,
    required this.grown,
    required this.dye,
  });

  // Half the width of the dish's opening, for a held sphere's radius.
  static double _rimHalfWidth(double radius, double gap) => radius * 1.05 + gap;
  // The opening's ellipse is this flat, as a share of its half-width.
  static const _rimFlatness = 0.28;
  // A quarter sphere: the dish is half as deep as its opening is wide.
  static const _depthShare = 0.5;

  /* Distance from a held sphere's centre down to its dish's base. The
     opening sits [gap] below the sphere's bottom, so the dish's front
     wall never covers the sphere. */
  static double depthBelowCenter(double radius, double gap) =>
      radius + gap + _rimHalfWidth(radius, gap) * _depthShare;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeOut.transform(grown.clamp(0.0, 1.0));
    final ink = Color.lerp(dye, AppColors.textPrimary, 0.4)!;
    final down = Offset(math.sin(tilt), math.cos(tilt));

    if (!front) {
      // Stick: from the bowl's base along its lean to the screen's edge.
      final reach = (bottom - base.dy) / down.dy + 8;
      canvas.drawLine(
        base,
        base + down * (reach * t),
        Paint()
          ..color = ink
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round,
      );
    }

    // Draw the dish upright from its base, then lean it; it swells out
    // from its base as it grows.
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(-tilt);
    canvas.scale(t);
    final rimW = _rimHalfWidth(radius, gap);
    final rimH = rimW * _rimFlatness;
    final rimY = -rimW * _depthShare;
    final rim = Rect.fromCenter(center: Offset(0, rimY), width: rimW * 2, height: rimH * 2);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = ink;

    if (!front) {
      // The bowl's inside, seen through its opening: darker at the back.
      canvas.drawOval(
        rim,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(dye, ink, 0.55)!, Color.lerp(Colors.white, dye, 0.6)!],
          ).createShader(rim),
      );
      canvas.drawOval(rim, outline);
    } else {
      // Front wall: from the rim's near edge down round the base and back.
      final wall = Path()
        ..moveTo(-rimW, rimY)
        ..cubicTo(-rimW, rimY + (0 - rimY) * 1.33, rimW, rimY + (0 - rimY) * 1.33, rimW, rimY)
        ..arcTo(rim, 0, math.pi, false)
        ..close();
      canvas.drawPath(
        wall,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(Colors.white, dye, 0.45)!, Color.lerp(dye, ink, 0.45)!],
          ).createShader(Rect.fromLTRB(-rimW, rimY, rimW, 0)),
      );
      canvas.drawPath(wall, outline);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BowlPainter old) =>
      old.front != front ||
      old.base != base ||
      old.radius != radius ||
      old.bottom != bottom ||
      old.tilt != tilt ||
      old.grown != grown ||
      old.dye != dye;
}

/* The shelf: its top edge curves down in the middle, and it fills
   straight down to the bottom of the screen. Dyed with the open tab's
   colour, with a lighter lip along the top where the light catches it.
   [sunk] (0-1) slides it down out of sight and fades it, for horizontal
   mode. */
class _ShelfPainter extends CustomPainter {
  final double topEnd;
  final double sag;
  final Color dye;
  final double sunk;

  _ShelfPainter({required this.topEnd, required this.sag, required this.dye, this.sunk = 0});

  @override
  void paint(Canvas canvas, Size size) {
    if (sunk >= 1) return;
    final w = size.width;
    final h = size.height;
    final opacity = 1 - sunk;
    canvas.save();
    canvas.translate(0, (h - topEnd) * Curves.easeIn.transform(sunk));

    // A quadratic curve through the ends dips by half its control offset.
    final path = Path()
      ..moveTo(0, topEnd)
      ..quadraticBezierTo(w / 2, topEnd + sag * 2, w, topEnd)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawShadow(path.shift(const Offset(0, -3)), dye.withValues(alpha: opacity), 4, true);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(Colors.white, dye, 0.35)!.withValues(alpha: opacity),
            Color.lerp(Colors.white, dye, 0.75)!.withValues(alpha: opacity),
          ],
        ).createShader(Rect.fromLTWH(0, topEnd, w, h - topEnd)),
    );

    // Lip along the top edge, where light catches the shelf.
    final lip = Path()
      ..moveTo(0, topEnd + 1.5)
      ..quadraticBezierTo(w / 2, topEnd + sag * 2 + 1.5, w, topEnd + 1.5);
    canvas.drawPath(
      lip,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.9 * opacity),
    );
    final edge = Path()
      ..moveTo(0, topEnd)
      ..quadraticBezierTo(w / 2, topEnd + sag * 2, w, topEnd);
    canvas.drawPath(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Color.lerp(dye, AppColors.textPrimary, 0.25)!.withValues(alpha: 0.5 * opacity),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShelfPainter old) =>
      old.topEnd != topEnd || old.sag != sag || old.dye != dye || old.sunk != sunk;
}

/* Space for the end of a scrolling page shown above the shelf: the shelf's
   height plus a little breathing room, so the last item can scroll fully
   clear of the spheres while the rest of the page shows behind them.
   Outside a shelf screen it's just the breathing room plus any system inset. */
double shelfBottomSpace(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + 24;

/* Keeps a page that doesn't scroll (like the piano) out from behind the
   shelf, as pages used to be. */
class AboveShelf extends StatelessWidget {
  final Widget child;
  const AboveShelf({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      SafeArea(top: false, left: false, right: false, child: child);
}

/* A tab screen with the shelf taskbar. The page background is dyed with
   the open tab's colour; switching tabs sends that colour out as a wave
   of ripples from the tapped sphere until it fills the screen, and the
   shelf takes on the colour as it goes. */
class ShelfTabScaffold extends StatefulWidget {
  final List<ShelfNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool rotateItems;
  final Widget body;

  const ShelfTabScaffold({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.body,
    this.rotateItems = false,
  });

  // The page background for a tab colour: the app background, tinted.
  static Color backgroundFor(Color tabColor) => Color.lerp(AppColors.background, tabColor, 0.5)!;

  @override
  State<ShelfTabScaffold> createState() => _ShelfTabScaffoldState();
}

class _ShelfTabScaffoldState extends State<ShelfTabScaffold> with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
    value: 1,
  );
  final _stackKey = GlobalKey();
  late List<GlobalKey> _slotKeys = _keysFor(widget.items.length);

  late Color _from = _colorOf(widget.currentIndex);
  late Color _to = _from;
  // Where the wave starts, in the stack's coordinates.
  Offset _origin = Offset.zero;

  static List<GlobalKey> _keysFor(int n) => List.generate(n, (_) => GlobalKey());

  Color _colorOf(int i) => widget.items[i.clamp(0, widget.items.length - 1)].color;

  // The tab colour on screen right now, part way through a wave or not.
  Color get _current => Color.lerp(_from, _to, Curves.easeOut.transform(_wave.value))!;

  @override
  void didUpdateWidget(covariant ShelfTabScaffold old) {
    super.didUpdateWidget(old);
    if (widget.items.length != old.items.length) {
      _slotKeys = _keysFor(widget.items.length);
    }
    if (widget.currentIndex != old.currentIndex) {
      _from = _current;
      _to = _colorOf(widget.currentIndex);
      _origin = _sphereCenter(widget.currentIndex) ?? _origin;
      if (MediaQuery.of(context).disableAnimations) {
        _wave.value = 1;
      } else {
        _wave.forward(from: 0);
      }
    }
  }

  // Roughly the middle of a tab's sphere, in the stack's coordinates.
  Offset? _sphereCenter(int i) {
    final slot = _slotKeys[i].currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (slot == null || stack == null) return null;
    final local = Offset(slot.size.width / 2, slot.size.height * 0.4);
    return stack.globalToLocal(slot.localToGlobal(local));
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _wave,
      builder: (context, child) => Scaffold(
        // The body runs behind the shelf, so the dye shows above its curve.
        extendBody: true,
        backgroundColor: AppColors.background,
        body: Stack(
          key: _stackKey,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _WavePainter(
                  from: ShelfTabScaffold.backgroundFor(_from),
                  to: ShelfTabScaffold.backgroundFor(_to),
                  ring: _to,
                  origin: _origin,
                  progress: _wave.value,
                ),
              ),
            ),
            child!,
          ],
        ),
        bottomNavigationBar: ShelfNavBar(
          items: widget.items,
          currentIndex: widget.currentIndex,
          onTap: widget.onTap,
          rotateItems: widget.rotateItems,
          dye: _current,
          slotKeys: _slotKeys,
        ),
      ),
      /* Built once per change of page, not every frame of the wave. The
         page runs down behind the shelf (no band cutting it off above the
         spheres); the shelf's height stays in MediaQuery's bottom padding,
         so each page ends its scrolling with shelfBottomSpace(). */
      child: SafeArea(bottom: false, child: widget.body),
    );
  }
}

/* The colour wave: the new colour spreads as a circle from [origin], led
   by three ripple rings (like rings in water), until it covers the
   screen. */
class _WavePainter extends CustomPainter {
  final Color from;
  final Color to;
  // Colour of the ripple rings.
  final Color ring;
  final Offset origin;
  final double progress;

  _WavePainter({
    required this.from,
    required this.to,
    required this.ring,
    required this.origin,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (progress >= 1) {
      canvas.drawRect(rect, Paint()..color = to);
      return;
    }
    canvas.drawRect(rect, Paint()..color = from);

    // Far enough to reach the furthest corner.
    final reach = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ].map((c) => (c - origin).distance).reduce(math.max);
    final radius = reach * Curves.easeOutCubic.transform(progress);
    canvas.drawCircle(origin, radius, Paint()..color = to);

    // Ripples just inside the wave's edge, fading as it spreads.
    final fade = 1 - progress;
    for (final (k, width) in [(1.0, 3.0), (0.78, 2.5), (0.56, 2.0)]) {
      canvas.drawCircle(
        origin,
        radius * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = ring.withValues(alpha: 0.55 * fade * k),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.progress != progress || old.from != from || old.to != to || old.origin != origin;
}
