import 'package:flutter/material.dart';

import '../navigation/app_navigation_service.dart';
import '../theme/app_colors.dart';

enum AppSnackKind { info, success, warning, error }

class _SnackPalette {
  final Color background;
  final Color border;
  final Color accent;
  final IconData icon;
  const _SnackPalette(this.background, this.border, this.accent, this.icon);
}

const _palettes = <AppSnackKind, _SnackPalette>{
  AppSnackKind.info: _SnackPalette(
    Color(0xFFEAF1F8),
    AppColors.primaryBlueDark,
    AppColors.primaryBlueDark,
    Icons.info_outline_rounded,
  ),
  AppSnackKind.success: _SnackPalette(
    Color(0xFFE6F4EA),
    AppColors.success,
    AppColors.success,
    Icons.check_circle_outline_rounded,
  ),
  AppSnackKind.warning: _SnackPalette(
    Color(0xFFFBF1DD),
    AppColors.warning,
    AppColors.warning,
    Icons.warning_amber_rounded,
  ),
  AppSnackKind.error: _SnackPalette(
    Color(0xFFFBE6E6),
    AppColors.danger,
    AppColors.danger,
    Icons.error_outline_rounded,
  ),
};

class AppSnackbar {
  AppSnackbar._();

  /* Show a soft, themed snackbar.

     Falls back to the global ScaffoldMessenger when no [BuildContext] is
     supplied, so it works from services / background callbacks. */
  static void show(
    String message, {
    BuildContext? context,
    AppSnackKind kind = AppSnackKind.info,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    final messenger = context != null
        ? ScaffoldMessenger.maybeOf(context)
        : AppNavigationService.scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    final palette = _palettes[kind]!;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: duration,
          backgroundColor: palette.background,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: palette.border.withValues(alpha: 0.4)),
          ),
          content: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.border.withValues(alpha: 0.3)),
                ),
                child: Icon(palette.icon, size: 18, color: palette.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          action: action,
        ),
      );
  }

  static void info(String msg, {BuildContext? context}) =>
      show(msg, context: context, kind: AppSnackKind.info);

  static void success(String msg, {BuildContext? context}) =>
      show(msg, context: context, kind: AppSnackKind.success);

  static void warning(String msg, {BuildContext? context}) =>
      show(msg, context: context, kind: AppSnackKind.warning);

  static void error(String msg, {BuildContext? context}) =>
      show(msg, context: context, kind: AppSnackKind.error);
}
