import 'dart:async';
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
   gently up and down (one full bob every 2 seconds). Tabs are icons only:
   names are left out to keep the bar calm and wordless for children
   ([showLabels] brings the open tab's name back). Screen readers still
   read each tab's name.

   On the sideways piano page the shelf sinks away and each sphere is held
   in its own cup on a stick instead, fanned out along the curve, and
   [rotateItems] turns the icons a quarter clockwise. Both changes are
   animated.

   [vertical] is for the phone turned to landscape: the bar is drawn the
   same way but shown turned a quarter anticlockwise (see
   [ShelfTabScaffold]), so the shelf stands along the right edge of the
   screen. The icons are turned back so they stay upright, and the open
   tab's name sits in a pill to the left of its sphere. */
class ShelfNavBar extends StatefulWidget {
  final List<ShelfNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool rotateItems;
  final bool vertical;
  // Colour the shelf is dyed with (the open tab's colour).
  final Color? dye;
  // One per tab, so [ShelfTabScaffold] can find where each sphere is.
  final List<GlobalKey>? slotKeys;
  // One per tab, on the sphere itself, so a guide can ring it exactly.
  final List<GlobalKey>? sphereKeys;
  // Show the open tab's name under (or beside) its sphere.
  final bool showLabels;

  const ShelfNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.rotateItems = false,
    this.vertical = false,
    this.dye,
    this.slotKeys,
    this.sphereKeys,
    this.showLabels = false,
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
  // The open tab's name. Its box grows with the app's text size so the
  // FittedBox never shrinks the text back down.
  static const _labelFontSize = 14.0;
  static const _sidePadding = 8.0;
  // Tilt of the outermost holders in horizontal mode, in radians.
  static const _fan = 0.55;
  // Space between a sphere and the inside of its bowl.
  static const _bowlGap = 3.0;

  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  /* 0 = shelf, 1 = cups on sticks. The cups need more room under the
     spheres than the shelf does, so the whole bar rebuilds through the
     morph and grows smoothly with them. */
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..addListener(() {
      if (mounted) setState(() {});
    });
  bool? _holders;

  /* The vertical bar's name pill floats over the page, so it only shows
     for a moment when a tab opens, then fades away. */
  static const _sideLabelTime = Duration(milliseconds: 2500);
  bool _sideLabelOn = false;
  Timer? _sideLabelTimer;

  void _flashSideLabel() {
    _sideLabelTimer?.cancel();
    if (!widget.vertical) return;
    _sideLabelOn = true;
    _sideLabelTimer = Timer(_sideLabelTime, () {
      if (mounted) setState(() => _sideLabelOn = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _flashSideLabel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMorph();
  }

  @override
  void didUpdateWidget(covariant ShelfNavBar old) {
    super.didUpdateWidget(old);
    _syncMorph();
    if (widget.currentIndex != old.currentIndex || widget.vertical != old.vertical) {
      _flashSideLabel();
    }
  }

  // Shelf or cups: cups only on the sideways piano page in portrait.
  void _syncMorph() {
    final holders = widget.rotateItems && !widget.vertical;
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
    _sideLabelTimer?.cancel();
    _bob.dispose();
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length;
    final still = MediaQuery.of(context).disableAnimations;
    final dye = widget.dye ?? AppColors.primaryBlue;

    final padding = MediaQuery.paddingOf(context);
    final labelHeight = widget.showLabels
        ? MediaQuery.textScalerOf(context).scale(_labelFontSize) * 1.35
        : 0.0;

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        /* Vertical: the bar's left end is the bottom of the screen and its
           right end the top, so keep the spheres clear of the gesture bar
           and the status bar there. */
        final startPad = _sidePadding + (widget.vertical ? padding.bottom : 0);
        final endPad = _sidePadding + (widget.vertical ? padding.top : 0);
        final slot = (width - startPad - endPad) / n;
        final d = math.min(slot * 0.7, 48.0);
        final big = d * _focusScale;
        // Shelf top at its ends: room above for an enlarged, bobbing sphere.
        final shelfTopEnd = big * (0.5 + _perch) + _bobAmplitude + 4;
        /* The shelf runs to the edge of the screen, under the system's
           navigation bar (or, standing on the right, under any inset
           there) too. That bar can be a thin gesture line or a tall,
           solid strip of back/home buttons, and either one covers what is
           drawn under it, so the spheres - and in cup mode their cups -
           always sit wholly above it. Standing on the right there is
           usually no inset, so keep a little shelf there all the same, or
           it is only a sliver. */
        final edgeInset = widget.vertical ? math.max(padding.right, 14.0) : padding.bottom;
        // How far a cup reaches below its (closed) sphere.
        final cupBelow = _BowlPainter.depthBelowCenter(d / 2, _bowlGap) - d / 2;
        // Room below a closed sphere, above the system bar: for the open
        // tab's bigger sphere and its label (60% - the label may tuck in a
        // little), or for the cups as they grow in.
        final aboveInset = math.max(
          0.6 * ((big - d) * (0.5 - _perch) + labelHeight + 4),
          cupBelow * Curves.easeInOut.transform(_morph.value),
        );
        final belowSphere = aboveInset + edgeInset + 2;
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
                  // Vertical: the bar's left end is the screen's bottom, so
                  // count from the other end to list the tabs top to bottom.
                  final pos = widget.vertical ? n - 1 - i : i;
                  final x = startPad + slot * (pos + 0.5);
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
                                sphereKey: widget.sphereKeys?[i],
                                d: d,
                                slot: slot,
                                shelfTop: shelfTopAt(x),
                                barHeight: height,
                                tilt: _fan * (x - width / 2) / (width / 2),
                                focus: focus,
                                bob: bob,
                                dye: dye,
                                labelHeight: labelHeight,
                                // Room for a wide label without running off
                                // the screen at either end.
                                labelRoomLeft: x - slot / 2,
                                labelRoomRight: width - (x + slot / 2),
                                showLabel: widget.showLabels &&
                                    selected &&
                                    (widget.vertical || !widget.rotateItems),
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
    required GlobalKey? sphereKey,
    required double d,
    required double slot,
    required double shelfTop,
    required double barHeight,
    required double tilt,
    required double focus,
    required double bob,
    required Color dye,
    required double labelHeight,
    required double labelRoomLeft,
    required double labelRoomRight,
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
            key: sphereKey,
            item: item,
            focus: focus.clamp(0.0, 1.0),
            // The vertical bar is turned a quarter anticlockwise, so a
            // quarter clockwise here keeps its icons upright.
            rotateIcon: widget.rotateItems || widget.vertical,
          ),
        ),
        // The dish's front wall (it sits below the sphere, never over it).
        if (_morph.value > 0)
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: bowl(true))),
          ),
        if (showLabel && widget.vertical)
          _sideLabel(item.label, center, size, labelHeight, focus.clamp(0.0, 1.0))
        else if (showLabel)
          Positioned(
            top: center.dy + size / 2 + 1,
            // Wider than the slot, so longer names like "Dashboard" keep
            // their full size; only the open tab has a label.
            left: -math.min(slot * 0.35, labelRoomLeft),
            right: -math.min(slot * 0.35, labelRoomRight),
            height: labelHeight,
            // Fades out in horizontal mode, where the holder sits there.
            child: Opacity(
              opacity: focus.clamp(0.0, 1.0) * (1 - m),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(item.label, maxLines: 1, style: _labelStyle),
              ),
            ),
          ),
      ],
    );
  }

  static const _labelStyle = TextStyle(
    fontSize: _labelFontSize,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  /* The vertical bar's label: a small pill to the left of the open sphere
     on screen. The bar is drawn turned a quarter anticlockwise, so "left
     on screen" is up here, and the pill is turned back to read normally. */
  Widget _sideLabel(String label, Offset center, double size, double labelHeight, double focus) {
    const maxWidth = 140.0;
    final thickness = labelHeight + 10;
    return Positioned(
      left: center.dx - thickness / 2,
      top: center.dy - size / 2 - 6 - maxWidth,
      width: thickness,
      height: maxWidth,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 400),
          opacity: _sideLabelOn ? focus : 0,
          child: RotatedBox(
            quarterTurns: 1,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(thickness / 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1, style: _labelStyle),
                ),
              ),
            ),
          ),
        ),
      ),
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

  const _NavSphere({super.key, required this.item, required this.focus, required this.rotateIcon});

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
  State<ShelfTabScaffold> createState() => ShelfTabScaffoldState();
}

class ShelfTabScaffoldState extends State<ShelfTabScaffold> with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
    value: 1,
  );
  final _stackKey = GlobalKey();
  late List<GlobalKey> _slotKeys = _keysFor(widget.items.length);
  late List<GlobalKey> _sphereKeys = _keysFor(widget.items.length);

  late Color _from = _colorOf(widget.currentIndex);
  late Color _to = _from;
  // Where the wave starts, in the stack's coordinates.
  Offset _origin = Offset.zero;

  static List<GlobalKey> _keysFor(int n) => List.generate(n, (_) => GlobalKey());

  Color _colorOf(int i) => widget.items[i.clamp(0, widget.items.length - 1)].color;

  // The tab colour on screen right now, part way through a wave or not.
  Color get _current => Color.lerp(_from, _to, Curves.easeOut.transform(_wave.value))!;

  @override
  void didUpdateWidget(covariant ShelfTabScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != oldWidget.items.length) {
      _slotKeys = _keysFor(widget.items.length);
      _sphereKeys = _keysFor(widget.items.length);
    }
    if (widget.currentIndex != oldWidget.currentIndex) {
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

  /* A tab's sphere on screen, exactly where it's drawn (bobbing, grown
     when open, sitting in its cup), for a guide to ring. Follows the
     bar's turn in landscape. */
  Rect? sphereRect(int i) {
    if (i < 0 || i >= _sphereKeys.length) return null;
    final sphere = _sphereKeys[i].currentContext?.findRenderObject() as RenderBox?;
    if (sphere == null || !sphere.attached || !sphere.hasSize) return null;
    return MatrixUtils.transformRect(sphere.getTransformTo(null), Offset.zero & sphere.size);
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vertical = MediaQuery.orientationOf(context) == Orientation.landscape;
    return AnimatedBuilder(
      animation: _wave,
      builder: (context, child) => vertical
          ? _buildVertical(child!)
          : _buildBottom(child!),
      /* Built once per change of page, not every frame of the wave. The
         page runs down behind the shelf (no band cutting it off above the
         spheres); the shelf's height stays in MediaQuery's bottom padding,
         so each page ends its scrolling with shelfBottomSpace(). */
      child: SafeArea(bottom: false, child: widget.body),
    );
  }

  Widget get _wavePaint => Positioned.fill(
    child: CustomPaint(
      painter: _WavePainter(
        from: ShelfTabScaffold.backgroundFor(_from),
        to: ShelfTabScaffold.backgroundFor(_to),
        ring: _to,
        origin: _origin,
        progress: _wave.value,
      ),
    ),
  );

  /* Landscape: the shelf stands along the right edge. The bar is laid out
     as usual and turned a quarter anticlockwise, so its shelf side faces
     the screen's edge. The page stops at the bar, and the bar looks after
     any inset on the right itself. */
  Widget _buildVertical(Widget page) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        key: _stackKey,
        children: [
          _wavePaint,
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeRight: true,
                  child: page,
                ),
              ),
              RotatedBox(
                quarterTurns: 3,
                child: ShelfNavBar(
                  items: widget.items,
                  currentIndex: widget.currentIndex,
                  onTap: widget.onTap,
                  rotateItems: widget.rotateItems,
                  vertical: true,
                  dye: _current,
                  slotKeys: _slotKeys,
                  sphereKeys: _sphereKeys,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottom(Widget page) {
    return Scaffold(
        // The body runs behind the shelf, so the dye shows above its curve.
        extendBody: true,
        backgroundColor: AppColors.background,
        body: Stack(
          key: _stackKey,
          children: [_wavePaint, page],
        ),
        bottomNavigationBar: ShelfNavBar(
          items: widget.items,
          currentIndex: widget.currentIndex,
          onTap: widget.onTap,
          rotateItems: widget.rotateItems,
          dye: _current,
          slotKeys: _slotKeys,
          sphereKeys: _sphereKeys,
        ),
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
