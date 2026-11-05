import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/* One stat as a soft coloured circle. The icon fills the circle as a faint
   picture behind the text; inside it, the number takes half the circle's
   height with the label under it. Its width decides the circle's size. */
class StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconBackground;
  final String value;
  final String label;

  const StatCard({
    super.key,
    required this.icon,
    required this.iconBackground,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          return Container(
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  icon,
                  size: size * 0.78,
                  color: AppColors.textPrimary.withValues(alpha: 0.13),
                ),
                // Number and label together use the middle 72% of the
                // height, where the circle is still wide enough for them.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // contain: short values grow to the full height, long
                    // ones (like "5h 12m") shrink to the width instead.
                    SizedBox(
                      width: size * 0.66,
                      height: size * 0.5,
                      child: FittedBox(
                        child: Text(
                          value,
                          maxLines: 1,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                    /* The label wraps onto up to three lines instead of
                       shrinking: three small circles in a row leave too
                       little width for "Total Listening" on one line. Its
                       built-in line breaks are dropped so it wraps to fit. */
                    SizedBox(
                      width: size * 0.66,
                      child: Text(
                        label.replaceAll('\n', ' '),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: (size * 0.1).clamp(8.5, 12.0),
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.05,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/* Lays out stat cards: up to three sit side by side in one row; four or
   more go two to a row, with an odd last card centred. */
class StatCardGroup extends StatelessWidget {
  final List<StatCard> cards;
  const StatCardGroup({super.key, required this.cards});

  static const _spacing = 12.0;

  @override
  Widget build(BuildContext context) {
    final perRow = cards.length <= 3 ? cards.length : 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            (constraints.maxWidth - _spacing * (perRow - 1)) / perRow;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: _spacing,
          runSpacing: 16,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}
