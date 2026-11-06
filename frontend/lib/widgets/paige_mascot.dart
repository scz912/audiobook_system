import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/* Paige, the open-book mascot, animated: hops in, bobs, waves, blinks, and
   "talks" while her speech bubble says hi.

   The artwork is split into layers under assets/branding/paige/ (made by
   tool_assets/split_mascot.py). Every layer shares the same 400x420 canvas,
   so stacking them at one size rebuilds the full drawing, and each moving
   part can turn or squash around a point given in that canvas's units.

   With "reduce motion" on (system setting), Paige stands still. */
class PaigeMascot extends StatefulWidget {
  const PaigeMascot({super.key, this.width = 220, this.greeting});

  final double width;

  // Text for the speech bubble. Null hides the bubble.
  final String? greeting;

  // Precaches the layers so they all appear in the same frame.
  static Future<void> precache() => Future.wait(_layers.map((path) {
        final loader = SvgAssetLoader(path);
        return svg.cache.putIfAbsent(
          loader.cacheKey(null),
          () => loader.loadBytes(null),
        );
      }));

  static const _dir = 'assets/branding/paige';
  static const _sparkles = '$_dir/sparkles.svg';
  static const _noteYellow = '$_dir/note_yellow.svg';
  static const _noteTeal = '$_dir/note_teal.svg';
  static const _armBack = '$_dir/arm_back.svg';
  static const _body = '$_dir/body.svg';
  static const _eyes = '$_dir/eyes.svg';
  static const _mouth = '$_dir/mouth.svg';
  static const _handWave = '$_dir/hand_wave.svg';
  static const _layers = [
    _sparkles, _noteYellow, _noteTeal, _armBack, _body, _eyes, _mouth, _handWave,
  ];

  @override
  State<PaigeMascot> createState() => _PaigeMascotState();
}

class _PaigeMascotState extends State<PaigeMascot>
    with TickerProviderStateMixin {
  // One loop of idle motion: wave + say hi, then rest and blink.
  static const _loopSeconds = 4.0;

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_loopSeconds * 1000).round()),
  );

  bool _ready = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    PaigeMascot.precache().whenComplete(() {
      if (!mounted) return;
      setState(() => _ready = true);
      _start();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      if (_ready) _start();
    }
  }

  void _start() {
    if (_reduceMotion) {
      _intro.value = 1;
      _loop.stop();
      _loop.value = 0;
      return;
    }
    _intro.forward(from: 0);
    _loop.repeat();
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  // A point on the 400x420 canvas as an Alignment, for pivots.
  static Alignment _at(double x, double y) =>
      Alignment(x / 200 - 1, y / 210 - 1);

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = w * 420 / 400;
    final unit = w / 400; // one canvas unit in logical pixels

    return SizedBox(
      width: w,
      height: h,
      child: !_ready
          ? null
          : AnimatedBuilder(
              animation: Listenable.merge([_intro, _loop]),
              builder: (context, _) {
                final t = _loop.value * _loopSeconds;
                final intro = _intro.value;
                final hop = Curves.elasticOut.transform(intro);
                final fadeIn = Curves.easeOut.transform(
                  (intro * 2.5).clamp(0.0, 1.0),
                );

                // Gentle bob, one per second.
                final bob = math.sin(2 * math.pi * t);
                final lift = -bob * 5 * unit;

                // Wave for the first 2.4s of each loop, easing in and out.
                final waveEnv = t < 2.4 ? math.sin(math.pi * t / 2.4) : 0.0;
                final waveAngle =
                    -0.08 + waveEnv * 0.30 * math.sin(2 * math.pi * 2.5 * t);

                // Mouth moves as if saying "hi" near the start of each loop.
                final talking = t > 0.15 && t < 1.05;
                final mouthScale = talking
                    ? 0.6 + 0.4 * (0.5 + 0.5 * math.cos(2 * math.pi * 3.3 * (t - 0.15)))
                    : 1.0;

                // A quick blink later in the loop.
                final blinkPhase = (t - 3.1) / 0.18;
                final eyeScale = blinkPhase > 0 && blinkPhase < 1
                    ? 1 - 0.9 * math.sin(math.pi * blinkPhase)
                    : 1.0;

                Widget layer(String asset) =>
                    SvgPicture.asset(asset, width: w, height: h);

                final character = Transform.translate(
                  offset: Offset(0, lift),
                  child: Transform.scale(
                    scaleX: 1 - bob * 0.008,
                    scaleY: 1 + bob * 0.012,
                    alignment: _at(200, 390),
                    child: Stack(
                      children: [
                        Transform.rotate(
                          angle: waveAngle,
                          alignment: _at(100, 232),
                          child: layer(PaigeMascot._armBack),
                        ),
                        layer(PaigeMascot._body),
                        Transform.scale(
                          scaleY: eyeScale,
                          alignment: _at(200, 166),
                          child: layer(PaigeMascot._eyes),
                        ),
                        Transform.scale(
                          scaleY: mouthScale,
                          alignment: _at(200, 206),
                          child: layer(PaigeMascot._mouth),
                        ),
                        Transform.rotate(
                          angle: waveAngle,
                          alignment: _at(100, 232),
                          child: layer(PaigeMascot._handWave),
                        ),
                      ],
                    ),
                  ),
                );

                // Notes drift on their own, out of step with each other.
                Widget floating(String asset, double phase, double amp) {
                  final s = math.sin(2 * math.pi * (t / 2 + phase));
                  return Transform.translate(
                    offset: Offset(s * 2 * unit, -s * amp * unit),
                    child: Transform.rotate(
                      angle: s * 0.06,
                      child: layer(asset),
                    ),
                  );
                }

                final twinkle = 0.55 + 0.45 * math.sin(2 * math.pi * t / 1.3);

                final greeting = widget.greeting;
                final bubbleIn = Curves.easeOutBack.transform(
                  ((intro - 0.35) / 0.65).clamp(0.0, 1.0),
                );
                final bubblePulse = talking
                    ? 1 + 0.04 * math.sin(math.pi * (t - 0.15) / 0.9)
                    : 1.0;

                return Opacity(
                  opacity: fadeIn,
                  child: Transform.translate(
                    offset: Offset(0, (1 - hop) * 40 * unit),
                    child: Transform.scale(
                      scale: 0.7 + 0.3 * hop,
                      alignment: _at(200, 398),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Ground shadow shrinks as Paige rises.
                          Positioned(
                            left: 80 * unit,
                            top: 388 * unit,
                            width: 240 * unit,
                            height: 20 * unit,
                            child: Transform.scale(
                              scaleX: 1 + bob * 0.06,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF26215C)
                                      .withValues(alpha: 0.12 - bob * 0.02),
                                  borderRadius: BorderRadius.all(
                                    Radius.elliptical(120 * unit, 10 * unit),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Opacity(
                            opacity: twinkle,
                            child: layer(PaigeMascot._sparkles),
                          ),
                          floating(PaigeMascot._noteYellow, 0, 7),
                          floating(PaigeMascot._noteTeal, 0.35, 6),
                          character,
                          if (greeting != null)
                            Positioned(
                              left: 150 * unit,
                              top: -62 * unit,
                              child: Transform.scale(
                                scale: bubbleIn * bubblePulse,
                                alignment: Alignment.bottomLeft,
                                child: _SpeechBubble(
                                  text: greeting,
                                  fontSize: 30 * unit,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text, required this.fontSize});

  final String text;
  final double fontSize;

  static const _ink = Color(0xFF26215C);

  @override
  Widget build(BuildContext context) {
    final r = fontSize * 0.9;
    return CustomPaint(
      painter: _BubblePainter(radius: r, stroke: fontSize * 0.14, tail: fontSize * 0.7),
      child: Padding(
        padding: EdgeInsets.fromLTRB(r * 0.9, r * 0.45, r * 0.9, r * 0.45 + fontSize * 0.7),
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: _ink,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

// White rounded bubble with a tail at the bottom-left pointing at Paige.
class _BubblePainter extends CustomPainter {
  _BubblePainter({required this.radius, required this.stroke, required this.tail});

  final double radius;
  final double stroke;
  final double tail;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Rect.fromLTWH(0, 0, size.width, size.height - tail);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(body, Radius.circular(radius)));
    final tailPath = Path()
      ..moveTo(radius * 0.9, body.bottom - stroke)
      ..lineTo(radius * 0.2, size.height)
      ..lineTo(radius * 2.0, body.bottom - stroke)
      ..close();
    final shape = Path.combine(PathOperation.union, path, tailPath);

    canvas.drawPath(
      shape.shift(Offset(0, stroke * 1.2)),
      Paint()..color = const Color(0xFF26215C).withValues(alpha: 0.15),
    );
    canvas.drawPath(shape, Paint()..color = Colors.white);
    canvas.drawPath(
      shape,
      Paint()
        ..color = const Color(0xFF26215C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.radius != radius || old.stroke != stroke || old.tail != tail;
}
