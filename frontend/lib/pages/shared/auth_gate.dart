import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_state.dart';
import '../../state/chat_state.dart';
import '../../state/community_state.dart';
import '../../state/friends_state.dart';
import '../../state/hub_state.dart';
import '../../state/profiles_state.dart';
import '../../state/settings_state.dart';
import '../caregiver/caregiver_shell.dart';
import '../independent/independent_shell.dart';
import '../onboarding/welcome_page.dart';
import 'login_page.dart';
import 'splash_page.dart';

// Decides whether to show the login page or the main app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /* Paige's hello on the loading screen plays once per app launch, and long
     enough to finish waving even when the saved login loads instantly.
     AuthGate is rebuilt when leaving Child Mode; that shouldn't replay it. */
  static const _minSplash = Duration(milliseconds: 2600);
  static bool _splashPlayed = false;

  AuthStatus? _lastStatus;
  String? _lastCaregiverId;
  bool _holdSplash = false;
  Timer? _splashTimer;
  // Whether this device has been through the welcome flow (null = loading).
  bool? _welcomeSeen;

  @override
  void initState() {
    super.initState();
    WelcomePage.seen().then((seen) {
      if (mounted) setState(() => _welcomeSeen = seen);
    });
    if (!_splashPlayed) {
      _splashPlayed = true;
      _holdSplash = true;
      _splashTimer = Timer(_minSplash, () {
        if (mounted) setState(() => _holdSplash = false);
      });
    }
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final caregiverId = auth.user?.caregiverId;

    // Only act when the login status or caregiver changes. This runs during
    // the splash too, so the caregiver's profiles load while Paige waves.
    if (auth.status != _lastStatus || caregiverId != _lastCaregiverId) {
      _lastStatus = auth.status;
      _lastCaregiverId = caregiverId;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _onAuthChanged(auth.status));
    }

    final showSplash = _holdSplash ||
        auth.status == AuthStatus.unknown ||
        (auth.status == AuthStatus.signedOut && _welcomeSeen == null);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(
        key: ValueKey(showSplash
            ? 'splash'
            : '${auth.status}-${auth.user?.accountType}-$_welcomeSeen'),
        child: showSplash ? const SplashPage() : _pageFor(auth),
      ),
    );
  }

  Widget _pageFor(AuthState auth) {
    switch (auth.status) {
      case AuthStatus.unknown:
        return const SplashPage();
      case AuthStatus.signedOut:
        // First time on this device: Paige's welcome, then an account.
        return _welcomeSeen == false
            ? WelcomePage(onLogin: () => setState(() => _welcomeSeen = true))
            : const LoginPage();
      case AuthStatus.signedIn:
        // A teenager on their own gets everything in one app.
        return auth.user?.isIndependent ?? false
            ? const IndependentShell()
            : const CaregiverShell();
    }
  }

  void _onAuthChanged(AuthStatus status) {
    if (!mounted) return;
    final profiles = context.read<ProfilesState>();
    final settings = context.read<SettingsState>();
    if (status == AuthStatus.signedIn) {
      // Has an account now: after logging out, show the login page.
      if (_welcomeSeen != true) setState(() => _welcomeSeen = true);
      // On sign-in, load this caregiver's profiles. On sign-out, clear them
      // so the next caregiver doesn't see old data.
      final caregiverId = context.read<AuthState>().user?.caregiverId;
      settings.clear();
      profiles.refresh(caregiverId: caregiverId);
    } else if (status == AuthStatus.signedOut) {
      profiles.clear();
      settings.clear();
      // Clear community data too, so nothing leaks to the next caregiver.
      context.read<CommunityState>().clear();
      context.read<FriendsState>().clear();
      context.read<ChatState>().clear();
      context.read<HubState>().clear();
    }
  }
}