import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';

/* A gentle "more below" cue for a page whose top is filled by big content
   (like the stat spheres): a small frosted pill with a softly bobbing
   arrow, sitting just above the shelf. Wraps the page's scroll view.

   - It shows when the page first opens at the top, until the reader
     scrolls.
   - After that it only comes back once the reader has done nothing on the
     page (no touch, no scroll) for [idleDelay] - wherever they are, as long
     as the [stopBefore] section hasn't come into view yet.
   - Any touch or scroll hides it again and restarts the wait.
   - Tapping it scrolls down for them. With reduced motion, the arrow is
     still. */
class ScrollMoreHint extends StatefulWidget {
  final ScrollController controller;
  final Widget child;
  // Tints the pill to match the page.
  final Color accent;
  // Distance from the bottom of the page (e.g. clear of the shelf).
  final double bottom;
  /* A section near the end: once it's on screen there's little left to
     hint at, so the hint stays away. Null = only the end of the page. */
  final GlobalKey? stopBefore;
  final Duration idleDelay;

  const ScrollMoreHint({
    super.key,
    required this.controller,
    required this.child,
    required this.accent,
    this.bottom = 16,
    this.stopBefore,
    this.idleDelay = const Duration(seconds: 90),
  });

  @override
  State<ScrollMoreHint> createState() => _ScrollMoreHintState();
}

class _ScrollMoreHintState extends State<ScrollMoreHint>
    with SingleTickerProviderStateMixin {
  // Not worth hinting at less than this much more page.
  static const _minMore = 80.0;

  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  final _pageKey = GlobalKey();
  Timer? _idle;
  bool _visible = false;
  // The first-visit hint, shown until the reader first scrolls.
  bool _introDone = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    // The page's size is known after its first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showIntro());
    _restartIdle();
  }

  @override
  void didUpdateWidget(ScrollMoreHint old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
    // Data may have just loaded and made the page long enough to hint at.
    if (!_introDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showIntro());
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    widget.controller.removeListener(_onScroll);
    _bob.dispose();
    super.dispose();
  }

  void _showIntro() {
    if (!mounted || _introDone) return;
    final c = widget.controller;
    final atTop = c.hasClients && c.position.pixels < 1;
    _setVisible(atTop && _worthHinting());
  }

  // The reader did something: hide the hint and start the wait again.
  void _onActivity() {
    _setVisible(false);
    _restartIdle();
  }

  void _onScroll() {
    final c = widget.controller;
    if (c.hasClients && c.position.pixels > 1) _introDone = true;
    _onActivity();
  }

  void _restartIdle() {
    _idle?.cancel();
    _idle = Timer(widget.idleDelay, () {
      if (mounted) _setVisible(_worthHinting());
    });
  }

  void _setVisible(bool v) {
    if (mounted && v != _visible) setState(() => _visible = v);
  }

  /* There's a fair bit more below, and the [stopBefore] section isn't on
     screen yet. */
  bool _worthHinting() {
    final c = widget.controller;
    if (!c.hasClients || !c.position.hasContentDimensions) return false;
    final p = c.position;
    if (p.maxScrollExtent - p.pixels < _minMore) return false;

    final stopCtx = widget.stopBefore?.currentContext;
    final pageBox = _pageKey.currentContext?.findRenderObject() as RenderBox?;
    // Not built yet: a lazy list only builds what's near the screen, so
    // the section is still well below.
    if (stopCtx == null || pageBox == null) return true;
    final stopBox = stopCtx.findRenderObject() as RenderBox?;
    if (stopBox == null || !stopBox.attached) return true;
    final stopTop = stopBox.localToGlobal(Offset.zero).dy;
    // The visible bottom of the page, above the hint's own spot.
    final pageBottom = pageBox.localToGlobal(Offset.zero).dy +
        pageBox.size.height -
        widget.bottom;
    return stopTop > pageBottom;
  }

  void _scrollDown() {
    final c = widget.controller;
    if (!c.hasClients) return;
    final p = c.position;
    final target = (p.pixels + p.viewportDimension * 0.7)
        .clamp(p.minScrollExtent, p.maxScrollExtent);
    if (MediaQuery.of(context).disableAnimations) {
      c.jumpTo(target);
    } else {
      c.animateTo(target,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: _pageKey,
      children: [
        // Any touch on the page counts as activity (taps included).
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _onActivity(),
          onPointerSignal: (_) => _onActivity(),
          child: widget.child,
        ),
        _pill(context),
      ],
    );
  }

  Widget _pill(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    final ink = Color.lerp(widget.accent, AppColors.textPrimary, 0.45)!;
    return Positioned(
      left: 0,
      right: 0,
      bottom: widget.bottom,
      child: IgnorePointer(
        ignoring: !_visible,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 280),
          child: AnimatedSlide(
            offset: _visible ? Offset.zero : const Offset(0, 0.4),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            child: Center(
              child: Semantics(
                button: true,
                label: context.tr('common.scroll_more'),
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: _scrollDown,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      // Frosted, so the page shows softly through it.
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 7, 12, 7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          // A glossy top like the spheres above it.
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.85),
                              Color.lerp(Colors.white, widget.accent, 0.35)!
                                  .withValues(alpha: 0.75),
                            ],
                          ),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.9)),
                          boxShadow: [
                            BoxShadow(
                              color: widget.accent.withValues(alpha: 0.28),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.tr('common.scroll_more'),
                              style: TextStyle(
                                color: ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            AnimatedBuilder(
                              animation: _bob,
                              builder: (_, child) => Transform.translate(
                                offset: Offset(
                                    0,
                                    still
                                        ? 0
                                        : Curves.easeInOut.transform(_bob.value) * 4 - 2),
                                child: child,
                              ),
                              child: Icon(Icons.keyboard_double_arrow_down_rounded,
                                  size: 18, color: ink),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
