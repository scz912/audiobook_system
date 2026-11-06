import 'package:flutter/material.dart';

// One colour per key, do (red) through to the high do (pink).
const pianoKeyColors = <Color>[
  Color(0xFFEF5350),
  Color(0xFFFF9800),
  Color(0xFFF9B822),
  Color(0xFF5CB860),
  Color(0xFF26BCD0),
  Color(0xFF42A5F5),
  Color(0xFF7E57C2),
  Color(0xFFEC407A),
];

const _solfege = ['Do', 'Re', 'Mi', 'Fa', 'So', 'La', 'Ti', 'Do'];
const _letters = ['C', 'D', 'E', 'F', 'G', 'A', 'B', 'C'];

/* The eight white keys of C major. Several fingers can play at once, and
   sliding a finger along the keys plays each one it passes over. */
class PianoKeyboard extends StatefulWidget {
  final ValueChanged<int> onKeyDown;
  const PianoKeyboard({super.key, required this.onKeyDown});

  @override
  State<PianoKeyboard> createState() => _PianoKeyboardState();
}

class _PianoKeyboardState extends State<PianoKeyboard> {
  // Which key each finger is on.
  final Map<int, int> _fingers = {};
  // Bumped on every strike so the key replays its animation.
  final List<int> _strikes = List.filled(_solfege.length, 0);

  int _keyAt(double dx, double width) =>
      (dx / width * _solfege.length).floor().clamp(0, _solfege.length - 1);

  void _press(int pointer, int key) {
    if (_fingers[pointer] == key) return;
    setState(() {
      _fingers[pointer] = key;
      _strikes[key]++;
    });
    widget.onKeyDown(key);
  }

  void _release(int pointer) {
    if (_fingers.remove(pointer) != null) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _press(e.pointer, _keyAt(e.localPosition.dx, box.maxWidth)),
        onPointerMove: (e) {
          final inside = e.localPosition.dy >= 0 && e.localPosition.dy <= box.maxHeight;
          if (inside) {
            _press(e.pointer, _keyAt(e.localPosition.dx, box.maxWidth));
          } else {
            _release(e.pointer);
          }
        },
        onPointerUp: (e) => _release(e.pointer),
        onPointerCancel: (e) => _release(e.pointer),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _solfege.length; i++)
              Expanded(
                child: _PianoKey(
                  solfege: _solfege[i],
                  letter: _letters[i],
                  color: pianoKeyColors[i],
                  pressed: _fingers.containsValue(i),
                  strikes: _strikes[i],
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _PianoKey extends StatefulWidget {
  final String solfege;
  final String letter;
  final Color color;
  final bool pressed;
  final int strikes;

  const _PianoKey({
    required this.solfege,
    required this.letter,
    required this.color,
    required this.pressed,
    required this.strikes,
  });

  @override
  State<_PianoKey> createState() => _PianoKeyState();
}

class _PianoKeyState extends State<_PianoKey> with SingleTickerProviderStateMixin {
  // Drives the little music note that floats up when the key is struck.
  late final AnimationController _note = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didUpdateWidget(covariant _PianoKey old) {
    super.didUpdateWidget(old);
    if (widget.strikes != old.strikes) _note.forward(from: 0);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pressed = widget.pressed;
    final color = widget.color;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      margin: EdgeInsets.fromLTRB(3, 0, 3, pressed ? 0 : 5),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(4),
          bottom: Radius.circular(18),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: pressed
              ? [Colors.white, Color.lerp(Colors.white, color, 0.35)!]
              : const [Colors.white, Color(0xFFF1F2F8)],
        ),
        boxShadow: [
          BoxShadow(
            color: pressed ? color.withValues(alpha: 0.55) : Colors.black26,
            blurRadius: pressed ? 16 : 3,
            offset: Offset(0, pressed ? 0 : 4),
          ),
        ],
      ),
      child: LayoutBuilder(builder: (context, box) {
        final badge = (box.maxWidth * 0.62).clamp(28.0, 64.0);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // Colour strip along the top of the key.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: pressed ? 1 : 0.7),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ),
            ),
            // Floating music note.
            AnimatedBuilder(
              animation: _note,
              builder: (context, _) {
                if (!_note.isAnimating) return const SizedBox.shrink();
                final t = Curves.easeOut.transform(_note.value);
                return Positioned(
                  bottom: badge + 18 + t * (box.maxHeight * 0.45),
                  child: Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: -0.3 + t * 0.4,
                      child: Icon(Icons.music_note_rounded, color: color, size: 26 + t * 8),
                    ),
                  ),
                );
              },
            ),
            // Note name badge.
            Positioned(
              bottom: 12,
              child: AnimatedScale(
                scale: pressed ? 1.12 : 1,
                duration: const Duration(milliseconds: 90),
                child: Container(
                  width: badge,
                  height: badge,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.solfege,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              shadows: [Shadow(color: Colors.black26, blurRadius: 3)],
                            ),
                          ),
                          Text(
                            widget.letter,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
