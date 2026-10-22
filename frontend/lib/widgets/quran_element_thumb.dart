import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/* Icon + tint for each nature element in the Al-Quran pack. Used before a
   chapter's GIF has been downloaded, and on the element chips. */
({IconData icon, Color color}) quranElementVisual(String elementId) {
  switch (elementId) {
    case 'fire':
      return (icon: Icons.local_fire_department_rounded, color: const Color(0xFFF7D2B8));
    case 'ocean':
      return (icon: Icons.waves_rounded, color: AppColors.iconCircleBlue);
    case 'forest':
      return (icon: Icons.forest_rounded, color: AppColors.iconCircleGreen);
    case 'rain':
      return (icon: Icons.water_drop_rounded, color: AppColors.iconCircleBlue);
    case 'thunder':
      return (icon: Icons.thunderstorm_rounded, color: AppColors.iconCirclePurple);
    case 'night_sky':
      return (icon: Icons.auto_awesome_rounded, color: AppColors.iconCirclePurple);
    case 'moon':
      return (icon: Icons.nightlight_round, color: AppColors.softLavender);
    case 'sunrise':
      return (icon: Icons.wb_twilight_rounded, color: AppColors.softYellow);
    case 'clouds':
      return (icon: Icons.cloud_rounded, color: AppColors.iconCircleBlue);
    case 'river':
      return (icon: Icons.water_rounded, color: AppColors.softMint);
    case 'desert':
      return (icon: Icons.wb_sunny_rounded, color: AppColors.iconCirclePeach);
    case 'mountain':
      return (icon: Icons.terrain_rounded, color: AppColors.iconCircleGreen);
    default:
      return (icon: Icons.eco_rounded, color: AppColors.iconCircleGreen);
  }
}

/* Square thumbnail for a chapter: its element GIF when downloaded,
   otherwise the element's icon on a tinted tile. */
class QuranElementThumb extends StatelessWidget {
  final String elementId;
  final File? gif;
  final double size;

  const QuranElementThumb({
    super.key,
    required this.elementId,
    this.gif,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final visual = quranElementVisual(elementId);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: visual.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(visual.icon, size: size * 0.45, color: AppColors.textPrimary),
    );
    if (gif == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        gif!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Decode small - the GIFs are ~480px wide but shown at 48px.
        cacheWidth: (size * 3).round(),
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
