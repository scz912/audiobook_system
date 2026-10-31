import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';

/* Choice of who can see an audiobook. [value] is 'private', 'public', or null
   when nothing has been picked yet. */
class VisibilityPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String> onChanged;
  const VisibilityPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _VisibilityOption(
          icon: Icons.lock_outline_rounded,
          label: context.tr('visibility.private'),
          hint: context.tr('visibility.private_hint'),
          selected: value == 'private',
          onTap: () => onChanged('private'),
        ),
        const SizedBox(height: 8),
        _VisibilityOption(
          icon: Icons.public_rounded,
          label: context.tr('visibility.public'),
          hint: context.tr('visibility.public_hint'),
          selected: value == 'public',
          onTap: () => onChanged('public'),
        ),
      ],
    );
  }
}

class _VisibilityOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;
  const _VisibilityOption({
    required this.icon,
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.iconCircleBlue : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? AppColors.primaryBlueDark : AppColors.cardBorder,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.primaryBlueDark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(hint,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primaryBlueDark),
            ],
          ),
        ),
      ),
    );
  }
}
