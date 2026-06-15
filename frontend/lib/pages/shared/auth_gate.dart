import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_state.dart';
import '../../state/profiles_state.dart';
import '../../state/settings_state.dart';
import '../caregiver/caregiver_shell.dart';
import 'login_page.dart';

// Decides whether to show the login page or the main app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthStatus? _lastStatus;
  String? _lastCaregiverId;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final caregiverId = auth.user?.caregiverId;

    // Only act when the login status or caregiver changes.
    if (auth.status != _lastStatus || caregiverId != _lastCaregiverId) {
      _lastStatus = auth.status;
      _lastCaregiverId = caregiverId;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _onAuthChanged(auth.status));
    }

    switch (auth.status) {
      case AuthStatus.unknown:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case AuthStatus.signedOut:
        return const LoginPage();
      case AuthStatus.signedIn:
        return const CaregiverShell();
    }
  }

  void _onAuthChanged(AuthStatus status) {
    if (!mounted) return;
    final profiles = context.read<ProfilesState>();
    final settings = context.read<SettingsState>();
    if (status == AuthStatus.signedIn) {
      // On sign-in, load this caregiver's profiles. On sign-out, clear them
      // so the next caregiver doesn't see old data.
      final caregiverId = context.read<AuthState>().user?.caregiverId;
      settings.clear();
      profiles.refresh(caregiverId: caregiverId);
    } else if (status == AuthStatus.signedOut) {
      profiles.clear();
      settings.clear();
    }
  }
}