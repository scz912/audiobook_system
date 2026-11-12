import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';

/* A small "Easy" / "Medium" / "Hard" tag in green, yellow or orange, laid
   over the top-right corner of an audiobook's cover. A white rim and a
   soft shadow keep it standing in front of any picture. Shows nothing for
   a book with no (or an unknown) difficulty. */
class DifficultyBadge extends StatelessWidget {
  final String? difficulty;
  const DifficultyBadge({super.key, required this.difficulty});

  static const _easy = Color(0xFF7BCB72);
  static const _medium = Color(0xFFFFD43B);
  static const _hard = Color(0xFFFF9F45);

  // The fill and the label key for a difficulty, or null when unknown.
  static (Color, String)? styleFor(String? difficulty) =>
      switch ((difficulty ?? '').trim().toLowerCase()) {
        'easy' => (_easy, 'content.difficulty_easy'),
        'medium' => (_medium, 'content.difficulty_medium'),
        'hard' => (_hard, 'content.difficulty_hard'),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final style = styleFor(difficulty);
    if (style == null) return const SizedBox.shrink();
    final label = context.tr(style.$2);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: style.$1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
