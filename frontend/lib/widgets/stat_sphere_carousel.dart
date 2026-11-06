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

class _Sphere extends StatelessWidget {
  final StatSphere sphere;
  final double size;
  // How much darker to draw it, for spheres at the back.
  final double dim;
  const _Sphere({required this.sphere, required this.size, required this.dim});

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
                  width: size * 0.66,
                  height: size * 0.4,
                  child: FittedBox(
                    child: Text(
                      sphere.value,
                      maxLines: 1,
                      style: TextStyle(
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
                    ),
                  ),
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
