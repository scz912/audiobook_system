import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_state.dart';
import '../../state/profiles_state.dart';
import '../../state/settings_state.dart';
import '../caregiver/caregiver_shell.dart';
import 'login_page.dart';

/// Switches between the LoginPage and CaregiverShell based on auth status,
/// and — crucially — fires the side effects that keep ProfilesState and
/// SettingsState in sync with the signed-in caregiver.
///
/// This used to live on a separate `_SessionScopedLoader` widget that
/// wrapped AuthGate at MaterialApp.home, but caregiver-mode entry/exit and
/// the logout button both use Navigator.pushReplacement / pushAndRemoveUntil
/// which unmount that wrapper. The result: a second login after a child-
/// mode round-trip never re-fetched profiles, and the dashboard came up
/// empty. Keeping the side effect on AuthGate itself means it works
/// anywhere AuthGate is mounted, no matter how the route stack was
/// reshuffled.
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

    // Fire the cross-state sync after the current frame paints — running
    // it synchronously here would call notifyListeners on other states
    // mid-build, which Provider asserts against.
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
      // Re-fetch profiles for whichever caregiver just signed in.
      // ProfilesState.refresh() drops the previous list when the caregiver
      // changes, so this also handles the "different account on the same
      // device" case without leaking the previous caregiver's children.
      final caregiverId = context.read<AuthState>().user?.caregiverId;
      settings.clear();
      profiles.refresh(caregiverId: caregiverId);
    } else if (status == AuthStatus.signedOut) {
      profiles.clear();
      settings.clear();
    }
  }
}