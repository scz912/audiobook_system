import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Routing
import 'navigation/app_navigation_service.dart';
import 'navigation/app_routes.dart';

// State
import 'state/auth_state.dart';
import 'state/language_state.dart';
import 'state/profiles_state.dart';
import 'state/settings_state.dart';

// Theme
import 'theme/app_theme.dart';

// Pages
import 'pages/shared/auth_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Default Flutter image cache is 1000 entries / 100 MB. Storybook pages
  // can be 800–1200 px JPEGs, and with 4–6 pages plus covers across the
  // child mode + caregiver content list the cache evicts itself, forcing
  // re-fetches from the backend over the emulator's slow HTTP loopback.
  // Bumping these up keeps already-loaded illustrations resident.
  PaintingBinding.instance.imageCache
    ..maximumSize = 250
    ..maximumSizeBytes = 250 << 20; // 250 MB
  runApp(const AudiobookApp());
}

class AudiobookApp extends StatelessWidget {
  const AudiobookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageState()..bootstrap()),
        ChangeNotifierProvider(create: (_) => AuthState()..bootstrap()),
        ChangeNotifierProvider(create: (_) => ProfilesState()),
        ChangeNotifierProvider(create: (_) => SettingsState()),
      ],
      child: MaterialApp(
        title: 'Audiobook for Autism',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        navigatorKey: AppNavigationService.navigatorKey,
        scaffoldMessengerKey: AppNavigationService.scaffoldMessengerKey,
        // AuthGate itself watches AuthState, switches between LoginPage and
        // CaregiverShell, AND fires the cross-state sync (profile refresh /
        // clear) on auth changes — see auth_gate.dart for the rationale.
        home: const AuthGate(),
        routes: AppRoutes.staticRoutes,
        onGenerateRoute: AppRoutes.onGenerateRoute,
      ),
    );
  }
}