import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';

/* Big Listen / Pause button and the round Back / Next buttons shared by the
   audiobook player and the Al-Quran player, so both feel the same. They show
   icons only, so a child doesn't need to read; the words are kept as
   screen-reader labels. */
class BigPlayButton extends StatelessWidget {
  final bool playing;
  final bool loading;
  final VoidCallback onTap;
  const BigPlayButton({
    super.key,
    required this.playing,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = loading
        ? context.tr('player.preparing')
        : context.tr(playing ? 'player.pause' : 'player.listen');
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 78,
          decoration: BoxDecoration(
            color: playing ? AppColors.primaryBlueDark : AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlueDark.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 52,
                ),
        ),
      ),
    );
  }
}

class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const RoundIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0.35,
          child: Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, size: 44, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}
