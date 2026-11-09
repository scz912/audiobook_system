import 'package:flutter/material.dart';

/* Text that never splits a word across two lines.

   Flutter breaks a word in the middle only when that one word is wider
   than the space it has (a long Malay word in a big title on a narrow
   phone, or with the phone's font size turned up). This measures the
   widest word and, if it wouldn't fit, shrinks the font just enough that
   it does, so lines only ever break between words.

   Needs a bounded width (inside a ListView, Column, Expanded...). Don't
   use it inside an AlertDialog: dialogs measure their content in a way a
   LayoutBuilder can't answer. */
class WholeWordsText extends StatelessWidget {
  const WholeWordsText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        var effective = DefaultTextStyle.of(context).style.merge(style);
        final size = effective.fontSize;
        if (box.maxWidth.isFinite && size != null) {
          final widest = widestWord(
            text,
            effective,
            MediaQuery.textScalerOf(context),
            Directionality.of(context),
          );
          if (widest > box.maxWidth) {
            // A hair under, so rounding never tips it back over.
            effective = effective.copyWith(fontSize: size * box.maxWidth / widest * 0.97);
          }
        }
        return Text(
          text,
          style: effective,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
        );
      },
    );
  }

  // How wide the widest single word is, drawn in [style].
  static double widestWord(
    String text,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
  ) {
    var widest = 0.0;
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    return widest;
  }
}
