import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../navigation/app_navigation_service.dart';
import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import 'auth_gate.dart';

// "Log out?" confirm, used by the dashboard and by Settings.
class LogoutDialog extends StatelessWidget {
  const LogoutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(context.tr('caregiver.logout_title')),
      content: Text(context.tr('caregiver.logout_body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('common.cancel')),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
          ),
          onPressed: () async {
            // Grab these before popping the dialog so we don't use a dead
            // context after the await.
            final auth = context.read<AuthState>();
            final navigator = AppNavigationService.navigatorKey.currentState;
            Navigator.pop(context);
            await auth.logout();
            // Child Mode swaps out AuthGate, so reset the stack to a fresh
            // one - now signed out, it shows the LoginPage.
            navigator?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthGate()),
              (route) => false,
            );
          },
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: Text(context.tr('caregiver.logout'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
