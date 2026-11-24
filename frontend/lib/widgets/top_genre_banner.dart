import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n/i18n.dart';

/* "Your top genre" banner on the Insights page (Top Music Genre): the
   genre played most on YouTube / YouTube Music in the last 30 days, with
   a look of its own - its colours, a big icon, and a motif drawn behind
   (bubbles for Pop, lightning for Rock, piano keys and a stave for
   Classical...). Drawn in code, so there are no image files to ship. */
class TopGenreBanner extends StatelessWidget {
  final String genre;
  final int plays;
  const TopGenreBanner({super.key, required this.genre, required this.plays});

  @override
  Widget build(BuildContext context) {
    final look = genreBannerLooks[genre] ?? _fallbackLook;
    final name = context.tr('music.genre.$genre');
    final tagline = context.tr('music.banner.$genre');
    final playsText = context.tr('music.banner_plays').replaceAll('{n}', '$plays');
    return Semantics(
      container: true,
      label: '${context.tr('music.your_top_genre')}: $name. $tagline. $playsText',
      excludeSemantics: true,
      child: Container(
        // At least this tall; taller with large system text.
        constraints: const BoxConstraints(minHeight: 164),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: look.colors,
          ),
          boxShadow: [
            BoxShadow(color: look.colors.last.withValues(alpha: 0.30), blurRadius: 18, offset: const Offset(0, 8)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [
              Positioned.fill(child: CustomPaint(painter: GenreMotifPainter(look.motif))),
              // The genre's icon, in a soft disc on the right.
              Positioned(
                right: 18,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
                    ),
                    child: Icon(look.icon, size: 50, color: Colors.white),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 124, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.emoji_events_rounded, size: 14, color: Colors.white),
                          const SizedBox(width: 5),
                          Text(
                            context.tr('music.your_top_genre'),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                          shadows: [Shadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontSize: 13, height: 1.25),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      playsText,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a genre's banner is drawn with behind the text.
enum GenreMotif {
  bubbles, hearts, lightning, spray, waves, equalizer, disco, spotlight, stave,
  film, hills, leaves, globe, confetti, night, balloons, rays,
}

typedef GenreBannerLook = ({List<Color> colors, IconData icon, GenreMotif motif});

/// Every listening genre's banner: gradient, icon and motif, all different.
const genreBannerLooks = <String, GenreBannerLook>{
  'pop': (colors: [Color(0xFFFF6FA8), Color(0xFFA855F7)], icon: Icons.mic_external_on_rounded, motif: GenreMotif.bubbles),
  'kpop': (colors: [Color(0xFF6D5BFF), Color(0xFFE0559E)], icon: Icons.auto_awesome_rounded, motif: GenreMotif.hearts),
  'rock': (colors: [Color(0xFF2B2D42), Color(0xFFD7263D)], icon: Icons.electric_bolt_rounded, motif: GenreMotif.lightning),
  'hiphop': (colors: [Color(0xFF232526), Color(0xFFB7791F)], icon: Icons.headphones_rounded, motif: GenreMotif.spray),
  'rnb': (colors: [Color(0xFF5B2A86), Color(0xFFC2477D)], icon: Icons.favorite_rounded, motif: GenreMotif.waves),
  'electronic': (colors: [Color(0xFF0F2027), Color(0xFF0089A8)], icon: Icons.graphic_eq_rounded, motif: GenreMotif.equalizer),
  'dance': (colors: [Color(0xFFE8590C), Color(0xFFA0153E)], icon: Icons.nightlife_rounded, motif: GenreMotif.disco),
  'jazz': (colors: [Color(0xFF1D3557), Color(0xFF9C6B30)], icon: Icons.music_note_rounded, motif: GenreMotif.spotlight),
  'classical': (colors: [Color(0xFF5C2A3D), Color(0xFF9E7647)], icon: Icons.piano_rounded, motif: GenreMotif.stave),
  'soundtrack': (colors: [Color(0xFF1B1B2F), Color(0xFF5B3F8C)], icon: Icons.movie_rounded, motif: GenreMotif.film),
  'country': (colors: [Color(0xFFD9622B), Color(0xFF7A4A21)], icon: Icons.landscape_rounded, motif: GenreMotif.hills),
  'folk': (colors: [Color(0xFF3F6E3B), Color(0xFF8A6D43)], icon: Icons.eco_rounded, motif: GenreMotif.leaves),
  'world': (colors: [Color(0xFF00796B), Color(0xFF1F6FB2)], icon: Icons.public_rounded, motif: GenreMotif.globe),
  'latin': (colors: [Color(0xFFD81B60), Color(0xFFE6501B)], icon: Icons.celebration_rounded, motif: GenreMotif.confetti),
  'ambient': (colors: [Color(0xFF2F4E6F), Color(0xFF6C5B7B)], icon: Icons.nights_stay_rounded, motif: GenreMotif.night),
  'children': (colors: [Color(0xFF2F7CF6), Color(0xFF8A5CF6)], icon: Icons.toys_rounded, motif: GenreMotif.balloons),
  'religious': (colors: [Color(0xFF2C5364), Color(0xFF5E8A6E)], icon: Icons.brightness_7_rounded, motif: GenreMotif.rays),
};

const GenreBannerLook _fallbackLook =
    (colors: [Color(0xFF5B7FA6), Color(0xFF8A6FB0)], icon: Icons.queue_music_rounded, motif: GenreMotif.bubbles);

/* Draws a genre's motif in translucent white over the banner. Shapes are
   placed by fractions of the size, so they sit the same on any width. */
class GenreMotifPainter extends CustomPainter {
  final GenreMotif motif;
  const GenreMotifPainter(this.motif);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Paint fill(double a) => Paint()..color = Colors.white.withValues(alpha: a);
    Paint line(double a, double width) => Paint()
      ..color = Colors.white.withValues(alpha: a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;

    switch (motif) {
      case GenreMotif.bubbles:
        for (final (x, y, r, a) in const [
          (0.62, 0.18, 22.0, 0.14), (0.92, 0.85, 34.0, 0.12), (0.55, 0.90, 12.0, 0.18),
          (0.98, 0.12, 16.0, 0.16), (0.70, 0.62, 8.0, 0.22), (0.45, 0.08, 6.0, 0.20),
        ]) {
          canvas.drawCircle(Offset(w * x, h * y), r, fill(a));
          canvas.drawCircle(Offset(w * x, h * y), r, line(a + 0.1, 1.5));
        }
        for (final (x, y, s) in const [(0.58, 0.45, 7.0), (0.80, 0.15, 5.0), (0.50, 0.70, 4.0)]) {
          _sparkle(canvas, Offset(w * x, h * y), s, fill(0.7));
        }
      case GenreMotif.hearts:
        for (final (x, y, s, a) in const [
          (0.60, 0.22, 14.0, 0.22), (0.95, 0.80, 20.0, 0.16), (0.52, 0.80, 9.0, 0.25), (0.82, 0.10, 8.0, 0.3),
        ]) {
          canvas.drawPath(_heart(Offset(w * x, h * y), s), fill(a));
        }
        for (final (x, y, r) in const [(0.68, 0.55, 6.0), (0.98, 0.35, 8.0), (0.47, 0.35, 5.0)]) {
          canvas.drawPath(_star(Offset(w * x, h * y), r, r * 0.45, 5), fill(0.5));
        }
        // A lightstick, tilted.
        canvas.save();
        canvas.translate(w * 0.70, h * 0.92);
        canvas.rotate(-0.5);
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-3, -34, 6, 30), const Radius.circular(3)), fill(0.35));
        canvas.drawCircle(const Offset(0, -42), 10, fill(0.3));
        canvas.restore();
      case GenreMotif.lightning:
        for (var i = -2; i < 8; i++) {
          final x = w * 0.45 + i * 26.0;
          canvas.drawLine(Offset(x, h), Offset(x + h * 0.6, 0), line(0.06, 10));
        }
        for (final (x, y, s) in const [(0.58, 0.12, 1.0), (0.96, 0.55, 1.3), (0.50, 0.62, 0.7)]) {
          canvas.drawPath(_bolt(Offset(w * x, h * y), s), fill(0.28));
        }
      case GenreMotif.spray:
        final rnd = math.Random(7);
        for (final (cx, cy, spread) in const [(0.60, 0.25, 26.0), (0.95, 0.80, 34.0), (0.50, 0.85, 18.0)]) {
          for (var i = 0; i < 40; i++) {
            final ang = rnd.nextDouble() * math.pi * 2;
            final d = math.sqrt(rnd.nextDouble()) * spread;
            canvas.drawCircle(Offset(w * cx + math.cos(ang) * d, h * cy + math.sin(ang) * d),
                rnd.nextDouble() * 2.2 + 0.6, fill(0.15 + rnd.nextDouble() * 0.2));
          }
        }
        // A crown, tagged on.
        final c = Offset(w * 0.66, h * 0.62);
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - 16, c.dy + 8)
            ..lineTo(c.dx - 18, c.dy - 10)
            ..lineTo(c.dx - 8, c.dy - 2)
            ..lineTo(c.dx, c.dy - 14)
            ..lineTo(c.dx + 8, c.dy - 2)
            ..lineTo(c.dx + 18, c.dy - 10)
            ..lineTo(c.dx + 16, c.dy + 8)
            ..close(),
          line(0.45, 2.5),
        );
      case GenreMotif.waves:
        for (var k = 0; k < 4; k++) {
          final path = Path();
          final base = h * (0.25 + k * 0.2);
          for (var x = w * 0.35; x <= w; x += 4) {
            final y = base + math.sin(x / 26 + k) * (8 + k * 2);
            x == w * 0.35 ? path.moveTo(x, y) : path.lineTo(x, y);
          }
          canvas.drawPath(path, line(0.18 + k * 0.05, 2.2));
        }
        canvas.drawPath(_heart(Offset(w * 0.56, h * 0.18), 9), fill(0.35));
      case GenreMotif.equalizer:
        for (var y = 0.0; y < h; y += 18) {
          canvas.drawLine(Offset(w * 0.4, y), Offset(w, y), line(0.05, 1));
        }
        final rnd = math.Random(3);
        const bar = 9.0, gap = 5.0;
        for (var x = w * 0.42; x < w; x += bar + gap) {
          final bh = h * (0.15 + rnd.nextDouble() * 0.55);
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x, h - bh, bar, bh), const Radius.circular(3)),
            fill(0.10 + rnd.nextDouble() * 0.12),
          );
          canvas.drawRect(Rect.fromLTWH(x, h - bh - 7, bar, 3), fill(0.45));
        }
      case GenreMotif.disco:
        final o = Offset(w * 0.78, -10);
        for (var i = 0; i < 9; i++) {
          final a = math.pi * (0.2 + i * 0.075);
          final far = Offset(o.dx + math.cos(a) * w, o.dy + math.sin(a) * w);
          final far2 = Offset(o.dx + math.cos(a + 0.03) * w, o.dy + math.sin(a + 0.03) * w);
          canvas.drawPath(Path()..moveTo(o.dx, o.dy)..lineTo(far.dx, far.dy)..lineTo(far2.dx, far2.dy)..close(),
              fill(i.isEven ? 0.10 : 0.05));
        }
        for (final (x, y, s) in const [(0.55, 0.30, 6.0), (0.62, 0.80, 8.0), (0.95, 0.88, 5.0), (0.48, 0.60, 4.0)]) {
          _sparkle(canvas, Offset(w * x, h * y), s, fill(0.75));
        }
      case GenreMotif.spotlight:
        canvas.drawPath(
          Path()..moveTo(w * 0.62, 0)..lineTo(w * 0.50, h)..lineTo(w * 0.80, h)..close(),
          fill(0.08),
        );
        canvas.drawPath(
          Path()..moveTo(w * 0.98, 0)..lineTo(w * 0.78, h)..lineTo(w * 1.05, h)..close(),
          fill(0.06),
        );
        _notes(canvas, size, const [(0.55, 0.18, '♪', 22.0), (0.60, 0.70, '♫', 26.0), (0.97, 0.20, '♩', 18.0)], 0.45);
      case GenreMotif.stave:
        for (var i = 0; i < 5; i++) {
          final path = Path();
          for (var x = w * 0.38; x <= w; x += 4) {
            final y = h * 0.16 + i * 9 + math.sin(x / 60) * 6;
            x == w * 0.38 ? path.moveTo(x, y) : path.lineTo(x, y);
          }
          canvas.drawPath(path, line(0.22, 1.2));
        }
        _notes(canvas, size, const [(0.52, 0.18, '♩', 20.0), (0.62, 0.12, '♪', 20.0)], 0.6);
        // Piano keys along the bottom.
        const key = 16.0;
        for (var x = w * 0.38; x < w; x += key) {
          canvas.drawRect(Rect.fromLTWH(x, h - 30, key - 2, 30), fill(0.16));
        }
        var n = 0;
        for (var x = w * 0.38; x < w; x += key, n++) {
          if (n % 7 == 2 || n % 7 == 6) continue;
          canvas.drawRect(Rect.fromLTWH(x + key * 0.65, h - 30, key * 0.6, 18), fill(0.35));
        }
      case GenreMotif.film:
        for (final top in [true, false]) {
          final y = top ? 0.0 : h - 22;
          canvas.drawRect(Rect.fromLTWH(w * 0.36, y, w, 22), fill(0.14));
          for (var x = w * 0.36 + 6; x < w; x += 18) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTWH(x, y + 6, 9, 10), const Radius.circular(2)),
              Paint()..color = Colors.black.withValues(alpha: 0.25),
            );
          }
        }
        for (final (x, y, r) in const [(0.58, 0.50, 6.0), (0.97, 0.45, 9.0)]) {
          canvas.drawPath(_star(Offset(w * x, h * y), r, r * 0.45, 5), fill(0.4));
        }
      case GenreMotif.hills:
        canvas.drawCircle(Offset(w * 0.62, h * 0.32), 24, fill(0.22));
        for (var i = 0; i < 10; i++) {
          final a = i * math.pi / 5;
          final c = Offset(w * 0.62, h * 0.32);
          canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * 30, c + Offset(math.cos(a), math.sin(a)) * 38,
              line(0.25, 2));
        }
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.35, h)
            ..quadraticBezierTo(w * 0.55, h * 0.55, w * 0.75, h * 0.82)
            ..quadraticBezierTo(w * 0.90, h * 0.62, w, h * 0.70)
            ..lineTo(w, h)
            ..close(),
          fill(0.14),
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.45, h)
            ..quadraticBezierTo(w * 0.72, h * 0.72, w, h * 0.88)
            ..lineTo(w, h)
            ..close(),
          fill(0.12),
        );
      case GenreMotif.leaves:
        for (final (x, y, s, rot) in const [
          (0.58, 0.20, 16.0, 0.6), (0.96, 0.82, 22.0, -0.8), (0.52, 0.78, 12.0, 2.2),
          (0.75, 0.08, 10.0, -2.0), (0.68, 0.60, 9.0, 1.2),
        ]) {
          canvas.save();
          canvas.translate(w * x, h * y);
          canvas.rotate(rot);
          canvas.drawPath(
            Path()
              ..moveTo(0, -s)
              ..quadraticBezierTo(s * 0.8, 0, 0, s)
              ..quadraticBezierTo(-s * 0.8, 0, 0, -s),
            fill(0.32),
          );
          canvas.drawLine(Offset(0, -s), Offset(0, s), line(0.4, 1.2));
          canvas.restore();
        }
      case GenreMotif.globe:
        final c = Offset(w * 0.86, h * 0.5);
        final r = h * 0.62;
        canvas.drawCircle(c, r, line(0.18, 1.5));
        for (final k in [0.35, 0.7]) {
          canvas.drawOval(Rect.fromCenter(center: c, width: r * 2 * k, height: r * 2), line(0.14, 1.2));
        }
        for (final f in [-0.5, 0.0, 0.5]) {
          final y = c.dy + r * f;
          final half = math.sqrt(r * r - (r * f) * (r * f));
          canvas.drawLine(Offset(c.dx - half, y), Offset(c.dx + half, y), line(0.14, 1.2));
        }
        // A dotted flight path.
        for (var t = 0.0; t <= 1; t += 0.06) {
          final p = Offset(w * (0.45 + t * 0.3), h * (0.85 - math.sin(t * math.pi) * 0.6));
          canvas.drawCircle(p, 1.8, fill(0.4));
        }
      case GenreMotif.confetti:
        final rnd = math.Random(11);
        for (var i = 0; i < 34; i++) {
          final p = Offset(w * (0.40 + rnd.nextDouble() * 0.62), h * rnd.nextDouble());
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(rnd.nextDouble() * math.pi);
          final a = 0.28 + rnd.nextDouble() * 0.35;
          if (i % 3 == 0) {
            canvas.drawCircle(Offset.zero, 3.2, fill(a));
          } else {
            canvas.drawRect(const Rect.fromLTWH(-5, -2, 10, 4), fill(a));
          }
          canvas.restore();
        }
      case GenreMotif.night:
        final m = Offset(w * 0.60, h * 0.28);
        canvas.drawPath(
          Path.combine(
            PathOperation.difference,
            Path()..addOval(Rect.fromCircle(center: m, radius: 18)),
            Path()..addOval(Rect.fromCircle(center: m + const Offset(8, -6), radius: 16)),
          ),
          fill(0.4),
        );
        for (final (x, y, s) in const [(0.50, 0.12, 1.6), (0.72, 0.45, 1.2), (0.96, 0.18, 1.8), (0.55, 0.62, 1.0)]) {
          canvas.drawCircle(Offset(w * x, h * y), s, fill(0.7));
        }
        for (final (x, y, s) in const [(0.62, 0.88, 1.0), (0.98, 0.78, 1.3)]) {
          final c = Offset(w * x, h * y);
          for (final (dx, dy, r) in const [(-18.0, 4.0, 12.0), (0.0, -4.0, 16.0), (18.0, 4.0, 12.0)]) {
            canvas.drawCircle(c + Offset(dx * s, dy * s), r * s, fill(0.10));
          }
        }
      case GenreMotif.balloons:
        for (final (x, y, s, a) in const [(0.58, 0.30, 1.0, 0.25), (0.98, 0.36, 1.2, 0.2), (0.66, 0.70, 0.8, 0.3)]) {
          final c = Offset(w * x, h * y);
          canvas.drawOval(Rect.fromCenter(center: c, width: 26 * s, height: 32 * s), fill(a));
          final string = Path()..moveTo(c.dx, c.dy + 16 * s);
          string.quadraticBezierTo(c.dx - 6, c.dy + 30 * s, c.dx + 2, c.dy + 44 * s);
          canvas.drawPath(string, line(0.3, 1.2));
        }
        for (final (x, y, r) in const [(0.50, 0.12, 6.0), (0.78, 0.15, 5.0), (0.90, 0.85, 7.0)]) {
          canvas.drawPath(_star(Offset(w * x, h * y), r, r * 0.45, 5), fill(0.45));
        }
      case GenreMotif.rays:
        final o = Offset(w * 0.86, h * 0.5);
        for (var i = 0; i < 16; i++) {
          final a = i * math.pi / 8;
          canvas.drawLine(o + Offset(math.cos(a), math.sin(a)) * 56, o + Offset(math.cos(a), math.sin(a)) * (90 + (i.isEven ? 30 : 0)),
              line(0.12, 3));
        }
        canvas.drawCircle(o, 60, fill(0.07));
        for (final (x, y, s) in const [(0.55, 0.20, 5.0), (0.60, 0.78, 4.0)]) {
          _sparkle(canvas, Offset(w * x, h * y), s, fill(0.6));
        }
    }
  }

  // A four-point twinkle.
  static void _sparkle(Canvas canvas, Offset c, double s, Paint p) {
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - s * 2)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + s * 2, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + s * 2)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - s * 2, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - s * 2),
      p,
    );
  }

  static Path _heart(Offset c, double s) => Path()
    ..moveTo(c.dx, c.dy + s)
    ..cubicTo(c.dx - s * 1.6, c.dy - s * 0.2, c.dx - s * 0.7, c.dy - s * 1.4, c.dx, c.dy - s * 0.5)
    ..cubicTo(c.dx + s * 0.7, c.dy - s * 1.4, c.dx + s * 1.6, c.dy - s * 0.2, c.dx, c.dy + s)
    ..close();

  static Path _star(Offset c, double outer, double inner, int points) {
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / points;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  static Path _bolt(Offset c, double s) => Path()
    ..moveTo(c.dx + 6 * s, c.dy - 22 * s)
    ..lineTo(c.dx - 10 * s, c.dy + 2 * s)
    ..lineTo(c.dx - 1 * s, c.dy + 2 * s)
    ..lineTo(c.dx - 6 * s, c.dy + 22 * s)
    ..lineTo(c.dx + 10 * s, c.dy - 4 * s)
    ..lineTo(c.dx + 1 * s, c.dy - 4 * s)
    ..close();

  static void _notes(Canvas canvas, Size size, List<(double, double, String, double)> notes, double alpha) {
    for (final (x, y, glyph, fontSize) in notes) {
      final tp = TextPainter(
        text: TextSpan(
          text: glyph,
          style: TextStyle(fontSize: fontSize, color: Colors.white.withValues(alpha: alpha)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width * x, size.height * y));
    }
  }

  @override
  bool shouldRepaint(GenreMotifPainter old) => old.motif != motif;
}
