import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/i18n.dart';
import 'paige_mascot.dart';

/* Things a guide step can wait for. The step moves on by itself when the
   person does it, so the tour is learned by doing, not just reading. */
enum GuideEvent {
  moodPicked,
  notePlayed,
  recordingStarted,
  recordingStopped,
  recordingSaved,
}

/* One step of a guide: what Paige says, which tab to show, and what to
   ring with the spotlight. */
class GuideStep {
  const GuideStep(
    this.textKey, {
    this.tab,
    this.spotlightTab = false,
    this.target,
    this.waitFor,
    this.onStart,
    this.turned = false,
    this.celebrate = false,
  });

  // What Paige says (a translation key). Keep it to one short line.
  final String textKey;
  // Open this tab when the step starts.
  final int? tab;
  // Ring that tab's circle in the taskbar.
  final bool spotlightTab;
  // Or ring this widget.
  final GlobalKey? target;
  // Move on by itself when this happens.
  final GuideEvent? waitFor;
  // Anything else to set up, like switching the story shelf.
  final VoidCallback? onStart;
  // Draw Paige a quarter turn round, to match the sideways piano page.
  final bool turned;
  // Confetti and a big Paige, for the last steps.
  final bool celebrate;
}

/* Runs a guide: which step is showing, moving on, skipping. The shell that
   owns it opens tabs through [openTab] and shows a GuideOverlay while it's
   [active]. */
class GuideController extends ChangeNotifier {
  GuideController({
    required this.steps,
    required this.openTab,
    required this.onFinish,
  });

  final List<GuideStep> steps;
  final void Function(int tab) openTab;
  // Called when the guide ends, finished or skipped.
  final VoidCallback onFinish;

  int _index = -1;

  bool get active => _index >= 0;
  int get index => _index;
  GuideStep? get step => active ? steps[_index] : null;
  bool get isLast => _index == steps.length - 1;

  void start() => _go(0);

  void next() => isLast ? finish() : _go(_index + 1);

  void finish() {
    if (!active) return;
    _index = -1;
    notifyListeners();
    onFinish();
  }

  // Something happened in the app; move on if this step was waiting for it.
  void report(GuideEvent event) {
    if (step?.waitFor == event) next();
  }

  void _go(int i) {
    _index = i;
    final s = steps[i];
    if (s.tab != null) openTab(s.tab!);
    s.onStart?.call();
    notifyListeners();
  }
}

/* Remembers which guides have been seen on this device. */
class GuideMemory {
  GuideMemory._();

  static Future<bool> isDone(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('guide_done.$key') ?? false;
  }

  static Future<void> markDone(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('guide_done.$key', true);
  }
}

// Where a widget is on screen, following any turn (like the sideways piano).
Rect? globalRectOf(GlobalKey key) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.attached || !box.hasSize) return null;
  return MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
}

/* The guide on top of a shell: the screen dims except for a pulsing ring
   round the thing being shown, and Paige explains it in a speech bubble
   with a big Next button. Skip is always in the top-right corner. Touches
   pass through the dimming, so the person can tap what Paige points at. */
class GuideOverlay extends StatefulWidget {
  const GuideOverlay({
    super.key,
    required this.controller,
    required this.tabRect,
  });

  final GuideController controller;
  // Where a tab's circle is on screen, for spotlightTab steps.
  final Rect? Function(int tab) tabRect;

  @override
  State<GuideOverlay> createState() => _GuideOverlayState();
}

class _GuideOverlayState extends State<GuideOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    // Every frame: follow the target while pages slide and tabs change.
    _ticker = createTicker((elapsed) => setState(() => _elapsed = elapsed))
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Rect? _targetRect(GuideStep step) {
    if (step.target != null) return globalRectOf(step.target!);
    if (step.spotlightTab && step.tab != null) return widget.tabRect(step.tab!);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.controller.step;
    if (step == null) return const SizedBox.shrink();
    final still = MediaQuery.disableAnimationsOf(context);
    final pulse = still
        ? 0.5
        : 0.5 + 0.5 * math.sin(_elapsed.inMilliseconds / 1000 * 2 * math.pi / 1.4);
    final target = _targetRect(step);
    final size = MediaQuery.sizeOf(context);

    final content = _GuideContent(
      key: ValueKey(widget.controller.index),
      step: step,
      isLast: widget.controller.isLast,
      // Keep Paige away from what she's pointing at.
      atTop: step.turned
          ? false
          : target != null && target.center.dy > size.height / 2,
      onNext: widget.controller.next,
      onSkip: widget.controller.finish,
    );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Nothing to tap behind a celebration, so catch every touch.
          if (step.celebrate) const Positioned.fill(child: AbsorbPointer()),
          IgnorePointer(
            child: CustomPaint(
              painter: _SpotlightPainter(
                target: target,
                circle: step.spotlightTab && step.target == null,
                pulse: pulse,
              ),
            ),
          ),
          step.turned
              ? RotatedBox(quarterTurns: 1, child: content)
              : content,
        ],
      ),
    );
  }
}

class _GuideContent extends StatelessWidget {
  const _GuideContent({
    super.key,
    required this.step,
    required this.isLast,
    required this.atTop,
    required this.onNext,
    required this.onSkip,
  });

  final GuideStep step;
  final bool isLast;
  final bool atTop;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  static const _ink = Color(0xFF26215C);
  static const _sun = Color(0xFFFFC83D);

  @override
  Widget build(BuildContext context) {
    final card = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(scale: 0.85 + 0.15 * t, child: child),
      child: _card(context),
    );

    return SafeArea(
      child: Stack(
        children: [
          if (step.celebrate) const Positioned.fill(child: IgnorePointer(child: _Confetti())),
          Align(
            alignment: step.turned
                ? Alignment.bottomLeft
                : step.celebrate
                    ? Alignment.center
                    : atTop
                        ? Alignment.topCenter
                        : Alignment.bottomCenter,
            child: Padding(
              // Clear of Skip at the top, and of the taskbar at the bottom.
              padding: EdgeInsets.fromLTRB(16, atTop ? 72 : 16, 16, atTop ? 16 : 150),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: step.turned ? 420 : 520),
                /* Touches on Paige, the bubble or round Next stop here, so
                   a slightly-off tap never plays the piano (it reads raw
                   pointers) or opens whatever is beneath. */
                child: Listener(behavior: HitTestBehavior.opaque, child: card),
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 12,
            child: _SkipButton(onTap: onSkip),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context) {
    final paige = PaigeMascot(width: step.celebrate ? 150 : (step.turned ? 72 : 84));
    final bubble = Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _ink, width: 3),
        boxShadow: [
          BoxShadow(color: _ink.withValues(alpha: 0.18), offset: const Offset(0, 4)),
        ],
      ),
      child: Text(
        context.tr(step.textKey),
        style: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          color: _ink,
          height: 1.25,
        ),
      ),
    );

    final next = Semantics(
      button: true,
      label: context.tr(isLast ? 'guide.done' : 'guide.next'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onNext,
        child: Padding(
          // Extra room to hit, for small or shaky fingers.
          padding: const EdgeInsets.all(8),
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: _sun,
              shape: BoxShape.circle,
              border: Border.all(color: _ink, width: 3),
            ),
            child: Icon(
              isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
              size: 38,
              color: _ink,
            ),
          ),
        ),
      ),
    );

    if (step.celebrate) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          paige,
          const SizedBox(height: 8),
          bubble,
          const SizedBox(height: 8),
          next,
        ],
      );
    }
    // Next sits under the bubble, so the words get the full width.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            paige,
            const SizedBox(width: 6),
            Expanded(child: bubble),
          ],
        ),
        const SizedBox(height: 2),
        next,
      ],
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const StadiumBorder(side: BorderSide(color: Color(0xFF26215C), width: 2.5)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr('guide.skip'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF26215C),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.fast_forward_rounded, size: 22, color: Color(0xFF26215C)),
            ],
          ),
        ),
      ),
    );
  }
}

/* Dims the screen, leaving a hole round the target with a ring that
   gently pulses, so the eye goes straight to it. */
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.target, required this.circle, required this.pulse});

  final Rect? target;
  final bool circle;
  final double pulse;

  static const _ring = Color(0xFFFFC83D);

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Path()..addRect(Offset.zero & size);
    final t = target;
    if (t == null) {
      canvas.drawPath(screen, Paint()..color = Colors.black.withValues(alpha: 0.35));
      return;
    }
    final hole = Path();
    late final RRect ring;
    if (circle) {
      final r = t.shortestSide / 2 + 10;
      hole.addOval(Rect.fromCircle(center: t.center, radius: r));
      ring = RRect.fromRectAndRadius(
          Rect.fromCircle(center: t.center, radius: r + 4 + 4 * pulse), Radius.circular(r + 8));
    } else {
      final r = t.inflate(8);
      hole.addRRect(RRect.fromRectAndRadius(r, const Radius.circular(22)));
      ring = RRect.fromRectAndRadius(r.inflate(4 + 4 * pulse), const Radius.circular(26));
    }
    canvas.drawPath(
      Path.combine(PathOperation.difference, screen, hole),
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = _ring.withValues(alpha: 0.6 + 0.4 * pulse),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.target != target || old.pulse != pulse || old.circle != circle;
}

// A short burst of falling colour, for "you did it".
class _Confetti extends StatefulWidget {
  const _Confetti();

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) && !_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(painter: _ConfettiPainter(_c.value)),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);

  final double t;

  static const _colors = [
    Color(0xFFFF5D7D), Color(0xFFFFC83D), Color(0xFF1EC8B0),
    Color(0xFF7457F5), Color(0xFF6FBF73),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (t == 0 || t == 1) return;
    final rnd = math.Random(7); // same pattern every time
    for (var i = 0; i < 60; i++) {
      final x = rnd.nextDouble() * size.width;
      final speed = 0.6 + rnd.nextDouble() * 0.6;
      final y = -20 + (size.height + 40) * (t * speed).clamp(0.0, 1.0);
      final sway = math.sin(t * 8 + i) * 12;
      canvas.save();
      canvas.translate(x + sway, y);
      canvas.rotate(t * 6 + i);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-5, -3, 10, 6), const Radius.circular(2)),
        Paint()..color = _colors[i % _colors.length].withValues(alpha: 1 - t * 0.6),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
