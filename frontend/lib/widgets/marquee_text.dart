import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/* A title that is never cut off with "...": when it is too long for its
   space it moves slowly so the whole of it can be read. Text that fits
   just sits still.

   [maxLines] 1 (the default): one line that glides to the left, then
   loops - a second copy follows the first, so the start comes round again
   without a jump, rests for [pause] and sets off again.

   [maxLines] 2 or more: the text wraps as usual and shows that many lines.
   If it needs more, it rests for [pause], scrolls up line by line until
   its last line shows, rests there for [endPause], then fades back to the
   top and goes round again.

   The edge it scrolls out of fades softly. With the phone's "remove
   animations" setting on it doesn't move; a long text then shows one more
   line and ends in "...". Screen readers read the text once. */
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  // Where text that fits sits (and, for several lines, each line).
  final TextAlign textAlign;
  // How many lines it shows at once.
  final int maxLines;
  // How fast it moves, in logical pixels a second. Defaults to an easy
  // reading pace for each direction.
  final double? velocity;
  // Rest at the start of each loop, so the beginning can be read.
  final Duration pause;
  // Several lines: rest at the end before going round again.
  final Duration endPause;
  // One line: space between the end of the text and the copy after it.
  final double gap;

  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
    this.velocity,
    this.pause = const Duration(milliseconds: 1800),
    this.endPause = const Duration(milliseconds: 1500),
    this.gap = 56,
  }) : assert(maxLines >= 1);

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  static const _fade = 14.0;
  // Several lines: how long the fade back to the top takes, each way.
  static const _swapMs = 250.0;

  late final Ticker _ticker;
  final _elapsed = ValueNotifier(Duration.zero);
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => _elapsed.value = e);
  }

  // Starts or stops the scroll after this frame (not during layout).
  void _setRunning(bool run) {
    if (run == _running) return;
    _running = run;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_running && !_ticker.isActive) {
        _elapsed.value = Duration.zero;
        _ticker.start();
      } else if (!_running && _ticker.isActive) {
        _ticker.stop();
        _elapsed.value = Duration.zero;
      }
    });
  }

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    // A new text starts again from its beginning.
    if (old.text != widget.text && _ticker.isActive) {
      _ticker
        ..stop()
        ..start();
      _elapsed.value = Duration.zero;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  // A mask that fades [start] and [end] pixels along [vertical] or across.
  Shader _edgeFade(Rect rect, double start, double end, {required bool vertical}) {
    final length = vertical ? rect.height : rect.width;
    return LinearGradient(
      begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
      end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
      colors: const [
        Color(0x00FFFFFF),
        Color(0xFFFFFFFF),
        Color(0xFFFFFFFF),
        Color(0x00FFFFFF),
      ],
      stops: [0, start / length, 1 - end / length, 1],
    ).createShader(rect);
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final scaler = MediaQuery.textScalerOf(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final dir = Directionality.of(context);

    return LayoutBuilder(
      builder: (context, box) => widget.maxLines == 1
          ? _oneLine(box, style, scaler, dir, still)
          : _lines(box, style, scaler, dir, still),
    );
  }

  Widget _plain({required int maxLines}) => Text(
    widget.text,
    style: widget.style,
    textAlign: widget.textAlign,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
  );

  Widget _oneLine(
    BoxConstraints box,
    TextStyle style,
    TextScaler scaler,
    TextDirection dir,
    bool still,
  ) {
    final probe = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      textDirection: dir,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final textW = probe.width;
    final textH = probe.height;
    probe.dispose();

    final overflows = box.maxWidth.isFinite && textW > box.maxWidth;
    _setRunning(overflows && !still);
    if (!overflows || still) return _plain(maxLines: overflows ? 2 : 1);

    final velocity = widget.velocity ?? 35;
    final rtl = dir == TextDirection.rtl;
    final pauseMs = widget.pause.inMilliseconds;
    final moveMs = (textW + widget.gap) / velocity * 1000;
    final line = Text(widget.text, style: widget.style, maxLines: 1, softWrap: false);

    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        child: SizedBox(
          width: box.maxWidth,
          height: textH,
          child: ClipRect(
            child: ValueListenableBuilder<Duration>(
              valueListenable: _elapsed,
              builder: (context, elapsed, strip) {
                final t = elapsed.inMilliseconds % (pauseMs + moveMs);
                final shift = t < pauseMs ? 0.0 : (t - pauseMs) / 1000 * velocity;
                // Fade the edge the text leaves by only once it moves, so
                // the first letter is crisp while it rests.
                final leaving = shift > 0 ? _fade : 0.0;
                return ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => _edgeFade(
                    rect,
                    rtl ? _fade : leaving,
                    rtl ? leaving : _fade,
                    vertical: false,
                  ),
                  child: Transform.translate(
                    offset: Offset(rtl ? shift : -shift, 0),
                    child: strip,
                  ),
                );
              },
              child: OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                minWidth: 0,
                maxWidth: double.infinity,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [line, SizedBox(width: widget.gap), line],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lines(
    BoxConstraints box,
    TextStyle style,
    TextScaler scaler,
    TextDirection dir,
    bool still,
  ) {
    if (!box.maxWidth.isFinite) {
      _setRunning(false);
      return _plain(maxLines: widget.maxLines);
    }
    TextPainter probe(int? maxLines) => TextPainter(
      text: TextSpan(text: widget.text, style: style),
      textDirection: dir,
      textAlign: widget.textAlign,
      textScaler: scaler,
      maxLines: maxLines,
    )..layout(maxWidth: box.maxWidth);
    final whole = probe(null);
    final window = probe(widget.maxLines);
    final fullH = whole.height;
    final windowH = window.height;
    final overflows = window.didExceedMaxLines;
    whole.dispose();
    window.dispose();

    _setRunning(overflows && !still);
    if (!overflows || still) {
      return _plain(maxLines: overflows ? widget.maxLines + 1 : widget.maxLines);
    }

    final velocity = widget.velocity ?? 20;
    final travel = fullH - windowH;
    final pauseMs = widget.pause.inMilliseconds.toDouble();
    final moveMs = travel / velocity * 1000;
    final endMs = widget.endPause.inMilliseconds.toDouble();
    final loopMs = pauseMs + moveMs + endMs;

    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        child: SizedBox(
          width: box.maxWidth,
          height: windowH,
          child: ClipRect(
            child: ValueListenableBuilder<Duration>(
              valueListenable: _elapsed,
              builder: (context, elapsed, text) {
                final ms = elapsed.inMilliseconds.toDouble();
                final t = ms % loopMs;
                final shift = t < pauseMs
                    ? 0.0
                    : t < pauseMs + moveMs
                    ? (t - pauseMs) / 1000 * velocity
                    : travel;
                /* Back to the top: fade out at the very end of the rest at
                   the bottom, fade in at the start of the rest at the top
                   (not on the first time round - it starts there). */
                var opacity = 1.0;
                if (t > loopMs - _swapMs) {
                  opacity = (loopMs - t) / _swapMs;
                } else if (ms >= loopMs && t < _swapMs) {
                  opacity = t / _swapMs;
                }
                // Fade the top edge once lines have gone up past it, and
                // the bottom edge while more lines wait below.
                final top = shift > 0 ? _fade : 0.0;
                final bottom = shift < travel ? _fade : 0.0;
                return Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => _edgeFade(rect, top, bottom, vertical: true),
                    child: Transform.translate(offset: Offset(0, -shift), child: text),
                  ),
                );
              },
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Text(widget.text, style: widget.style, textAlign: widget.textAlign),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
