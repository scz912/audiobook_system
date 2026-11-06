import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../widgets/paige_mascot.dart';

/* Shown while the app starts up (checking the saved login). Paige hops in,
   waves and says hi; AuthGate swaps this out once loading is done. */
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  static const background = Color(0xFFFFF7E8);
  static const _ink = Color(0xFF26215C);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mascotWidth = math.min(size.width * 0.62, 280.0);

    return Scaffold(
      backgroundColor: background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.15),
            radius: 0.9,
            colors: [Color(0xFFFFE9A8), background],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Room above for the speech bubble.
                SizedBox(height: mascotWidth * 0.18),
                PaigeMascot(
                  width: mascotWidth,
                  greeting: context.tr('splash.hi'),
                ),
                const SizedBox(height: 28),
                Text(
                  context.tr('splash.loading'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _ink.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 16),
                const _BouncingDots(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BouncingDots extends StatefulWidget {
  const _BouncingDots();

  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  static const _colors = [Color(0xFFFF5D7D), Color(0xFFFFC83D), Color(0xFF1EC8B0)];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
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
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = (_c.value - i * 0.15) % 1.0;
          final up = phase < 0.4 ? math.sin(math.pi * phase / 0.4) : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Transform.translate(
              offset: Offset(0, -8 * up),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _colors[i],
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
