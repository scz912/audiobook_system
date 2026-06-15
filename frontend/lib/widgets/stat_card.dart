import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      // Label sits right under the value. Pages keep labels the same number
      // of lines so the cards don't leave a gap at the bottom.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
          // FittedBox shrinks the value so long ones (like "5h 12m") fit.
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
