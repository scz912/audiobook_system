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
  // Increase image cache limits to avoid caregiver profile pictures too aggressively.
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
        home: const AuthGate(), // Decides whether to show onboarding/login or the main app.
        routes: AppRoutes.staticRoutes,
        onGenerateRoute: AppRoutes.onGenerateRoute, 
      ),
    );
  }
}