import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/* The three shades a sphere is painted with: a light highlight where the
   light hits, the main colour, and a deep shade on the far edge. */
class SpherePalette {
  final Color highlight;
  final Color base;
  final Color shade;
  const SpherePalette(this.highlight, this.base, this.shade);

  static const blue = SpherePalette(Color(0xFFCFE4FA), Color(0xFF5B95D6), Color(0xFF2F5F9E));
  static const green = SpherePalette(Color(0xFFCDF2E0), Color(0xFF3DB287), Color(0xFF1F7656));
  static const purple = SpherePalette(Color(0xFFEADFFA), Color(0xFF9070CF), Color(0xFF5A3E98));
  static const teal = SpherePalette(Color(0xFFCFF3F2), Color(0xFF3BB3B8), Color(0xFF1F7479));
  static const pink = SpherePalette(Color(0xFFFADDE8), Color(0xFFE07A9E), Color(0xFFA03F63));
  static const peach = SpherePalette(Color(0xFFFFE6D1), Color(0xFFEE9A5C), Color(0xFFAD5E24));
}

class StatSphere {
  final IconData icon;
  final String value;
  final String label;
  final SpherePalette palette;

  const StatSphere({
    required this.icon,
    required this.value,
    required this.label,
    required this.palette,
  });
}

/* Stats as glossy spheres circling on a ring, like a slow carousel seen
   from the front: the nearest sphere is biggest, the ones behind smaller
   and further back. Dragging sideways spins the ring; let go and it
   coasts, then settles back to its slow turn. */
class StatSphereCarousel extends StatefulWidget {
  final List<StatSphere> spheres;
  const StatSphereCarousel({super.key, required this.spheres});

  @override
  State<StatSphereCarousel> createState() => _StatSphereCarouselState();
}

class _StatSphereCarouselState extends State<StatSphereCarousel>
    with SingleTickerProviderStateMixin {
  // One full turn every 30 seconds.
  static const _autoSpeed = 2 * math.pi / 30;
  // How quickly a fling slows back down to the auto speed.
  static const _friction = 1.6;

  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastTick = Duration.zero;

  // Ring rotation, in radians.
  double _angle = 0;
  // Radians per second.
  double _velocity = _autoSpeed;
  bool _dragging = false;
  // Pixels the ring's edge moves per radian, for turning drags into angle.
  double _radius = 1;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (_dragging || dt <= 0) return;
    // With "remove animations" on, only move when the user spins it.
    final target = MediaQuery.of(context).disableAnimations ? 0.0 : _autoSpeed;
    _velocity = target + (_velocity - target) * math.exp(-_friction * dt);
    if (_velocity.abs() < 1e-4 && target == 0) return;
    setState(() => _angle += _velocity * dt);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() => _angle += d.delta.dx / _radius);
  }

  void _onDragEnd(DragEndDetails d) {
    _dragging = false;
    _velocity = (d.velocity.pixelsPerSecond.dx / _radius).clamp(-12.0, 12.0);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.spheres.length;
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      /* A tight ring seen from a little above: the spheres overlap as a
         cluster, with the ones at the back sitting higher and in shadow
         behind the front one. These proportions keep the cluster inside
         the width at any angle. */
      final size = math.min(width * 0.5, 220.0);
      _radius = size * 0.52;
      final tilt = size * 0.33;
      final centerY = size * 0.75;
      final height = size * 1.68;

      // Place each sphere on the ring; depth 1 is nearest, -1 furthest.
      final placed = [
        for (var i = 0; i < n; i++)
          () {
            final a = _angle + i * 2 * math.pi / n;
            final depth = math.cos(a);
            final t = (depth + 1) / 2;
            return (
              index: i,
              x: math.sin(a) * _radius,
              y: depth * tilt,
              depth: depth,
              scale: lerpDouble(0.8, 1.0, t)!,
              dim: (1 - t) * 0.5,
            );
          }(),
      ]..sort((a, b) => a.depth.compareTo(b.depth));

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _dragging = true,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: () => _dragging = false,
        child: SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final p in placed)
                Positioned(
                  left: width / 2 + p.x - size / 2,
                  top: centerY + p.y - size / 2,
                  width: size,
                  height: size,
                  child: Transform.scale(
                    scale: p.scale,
                    child: _Sphere(sphere: widget.spheres[p.index], size: size, dim: p.dim),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

/* Stats as glossy spheres in a grid, two to a row. They don't turn; each
   one just bobs gently up and down in place, a little out of step with
   its neighbours. Every value uses the same font size - the largest that
   still fits the widest value - so the numbers read as one set. */
class FloatingSphereGrid extends StatefulWidget {
  final List<StatSphere> spheres;
  const FloatingSphereGrid({super.key, required this.spheres});

  @override
  State<FloatingSphereGrid> createState() => _FloatingSphereGridState();
}

class _FloatingSphereGridState extends State<FloatingSphereGrid>
    with SingleTickerProviderStateMixin {
  static const _perRow = 2;
  static const _spacing = 14.0;
  // How far a sphere drifts above and below its resting spot.
  static const _bob = 6.0;

  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  // Largest font size at which every value fits the sphere's value box.
  double _sharedFontSize(double size) {
    const probe = 100.0;
    var best = double.infinity;
    for (final s in widget.spheres) {
      final tp = TextPainter(
        text: TextSpan(
          text: s.value,
          style: const TextStyle(fontSize: probe, fontWeight: FontWeight.w900, height: 1.0),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      final fit = math.min(size * _Sphere.valueWidth / tp.width,
              size * _Sphere.valueHeight / tp.height) *
          probe;
      best = math.min(best, fit);
    }
    return best.isFinite ? best : size * 0.3;
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return LayoutBuilder(builder: (context, box) {
      final size = math.min((box.maxWidth - _spacing * (_perRow - 1)) / _perRow, 200.0);
      final fontSize = _sharedFontSize(size);
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: _spacing,
        runSpacing: 8,
        children: [
          for (var i = 0; i < widget.spheres.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: _bob),
              child: SizedBox(
                width: size,
                height: size,
                child: AnimatedBuilder(
                  animation: _float,
                  builder: (context, child) {
                    if (still) return child!;
                    // Each sphere starts at a different point in the bob.
                    final phase = (_float.value + i * 0.37) * 2 * math.pi;
                    return Transform.translate(
                      offset: Offset(0, math.sin(phase) * _bob),
                      child: child,
                    );
                  },
                  child: _Sphere(
                    sphere: widget.spheres[i],
                    size: size,
                    dim: 0,
                    valueFontSize: fontSize,
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _Sphere extends StatelessWidget {
  // The box the value is drawn in, as a share of the sphere's size.
  static const valueWidth = 0.66;
  static const valueHeight = 0.4;

  final StatSphere sphere;
  final double size;
  // How much darker to draw it, for spheres at the back.
  final double dim;
  /* A fixed size for the value, shared by a whole set of spheres. When
     null the value is scaled to fill its own box instead. */
  final double? valueFontSize;
  const _Sphere({
    required this.sphere,
    required this.size,
    required this.dim,
    this.valueFontSize,
  });

  Widget _valueText(SpherePalette p, double? fontSize) {
    return Text(
      sphere.value,
      maxLines: 1,
      softWrap: false,
      // The shared size is already worked out to fit; system text scaling
      // on top of it would push the widest value out of the sphere.
      textScaler: fontSize == null ? null : TextScaler.noScaling,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        color: Colors.white,
        height: 1.0,
        shadows: [
          Shadow(
            color: p.shade.withValues(alpha: 0.7),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = sphere.palette;
    return Semantics(
      label: '${sphere.label.replaceAll('\n', ' ')}: ${sphere.value}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Lit from the top left.
          gradient: RadialGradient(
            center: const Alignment(-0.35, -0.45),
            radius: 1.05,
            colors: [p.highlight, p.base, p.shade],
            stops: const [0.0, 0.48, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: p.shade.withValues(alpha: 0.35),
              blurRadius: size * 0.14,
              offset: Offset(0, size * 0.08),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              sphere.icon,
              size: size * 0.7,
              color: Colors.white.withValues(alpha: 0.14),
            ),
            // Glossy reflection.
            Positioned(
              top: size * 0.09,
              left: size * 0.2,
              child: Container(
                width: size * 0.36,
                height: size * 0.2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.elliptical(size * 0.18, size * 0.1)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.75),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: size * valueWidth,
                  height: size * valueHeight,
                  child: valueFontSize == null
                      ? FittedBox(child: _valueText(p, null))
                      : Center(child: _valueText(p, valueFontSize)),
                ),
                SizedBox(height: size * 0.02),
                SizedBox(
                  width: size * 0.7,
                  child: Text(
                    sphere.label.replaceAll('\n', ' '),
                    textAlign: TextAlign.center,
                    // Three lines fit longer labels like the Malay ones.
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: (size * 0.085).clamp(9.5, 14.0),
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.95),
                      height: 1.1,
                      shadows: [
                        Shadow(color: p.shade.withValues(alpha: 0.8), blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Back spheres are shaded a little, as if further from the light.
            if (dim > 0)
              Positioned.fill(
                child: DecoratedBox(
                  // Darkest on the side away from the light, so it still
                  // reads as a sphere rather than a flat grey disc.
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.35, -0.45),
                      radius: 1.05,
                      colors: [
                        const Color(0xFF1E2440).withValues(alpha: dim * 0.6),
                        const Color(0xFF1E2440).withValues(alpha: (dim * 1.3).clamp(0.0, 1.0)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
