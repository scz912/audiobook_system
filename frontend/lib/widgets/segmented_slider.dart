import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class SegmentedSliderItem<T> {
  final T value;
  final String label;
  final IconData icon;
  const SegmentedSliderItem(this.value, this.label, this.icon);
}

/* A pill-shaped switch with a white thumb that slides under the selected
   segment. Same look as the Linear / Interactive switch on the upload page,
   but for any number of segments. */
class SegmentedSlider<T> extends StatelessWidget {
  final List<SegmentedSliderItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;

  const SegmentedSlider({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final index = items.indexWhere((i) => i.value == value).clamp(0, items.length - 1);
    // Alignment runs -1 (left) .. 1 (right).
    final x = items.length == 1 ? 0.0 : -1 + 2 * index / (items.length - 1);
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.softLavender.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.cardBorder),
      ),
      // expand: the label row must fill the pill's height, or the labels
      // sit at the top instead of centred on the thumb.
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment(x, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / items.length,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(children: [for (final item in items) _segment(item)]),
        ],
      ),
    );
  }

  Widget _segment(SegmentedSliderItem<T> item) {
    final selected = item.value == value;
    final color =
        selected ? AppColors.primaryBlueDark : AppColors.textSecondary;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(item.value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          // Three labels share a phone-width bar, so shrink rather than wrap.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 18, color: color),
                const SizedBox(width: 6),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
