import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/* Compact circular back button — sits in the top-left of a page header.
   The `label` parameter is kept for backwards compatibility but is only
   shown as a tooltip; the button itself stays icon-only so it doesn't
   stretch full width. */
class BackPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const BackPill({super.key, this.label = 'Back', this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: Tooltip(
          message: label,
          child: InkWell(
            onTap: onTap ?? () => Navigator.of(context).maybePop(),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.cardBorder),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.arrow_back_rounded,
                size: 20,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
