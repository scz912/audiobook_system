import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Routing
import 'navigation/app_navigation_service.dart';
import 'navigation/app_routes.dart';

// State
import 'state/auth_state.dart';
import 'state/chat_state.dart';
import 'state/community_state.dart';
import 'state/friends_state.dart';
import 'state/hub_state.dart';
import 'state/language_state.dart';
import 'state/profiles_state.dart';
import 'state/settings_state.dart';

// Theme
import 'theme/app_theme.dart';

// Pages
import 'pages/shared/auth_gate.dart';

// How much bigger than its set size all text in the app is drawn.
const double appTextScale = 1.2;

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
        ChangeNotifierProvider(create: (_) => CommunityState()),
        ChangeNotifierProvider(create: (_) => FriendsState()),
        ChangeNotifierProvider(create: (_) => ChatState()),
        ChangeNotifierProvider(create: (_) => HubState()),
      ],
      child: MaterialApp(
        title: 'Audiobook for Autism', 
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        /* All text in the app is 20% bigger than its set size, on top of
           the phone's own text-size setting, so it is easier to read. Icons
           are not affected. */
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          final system = mq.textScaler.scale(14) / 14;
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(system * appTextScale)),
            child: child!,
          );
        },
        navigatorKey: AppNavigationService.navigatorKey,
        scaffoldMessengerKey: AppNavigationService.scaffoldMessengerKey,
        home: const AuthGate(), // Decides whether to show onboarding/login or the main app.
        routes: AppRoutes.staticRoutes,
        onGenerateRoute: AppRoutes.onGenerateRoute, 
      ),
    );
  }
}