import 'package:flutter/material.dart';

import '../pages/caregiver/caregiver_dashboard_page.dart';
import '../pages/caregiver/caregiver_shell.dart';
import '../pages/caregiver/content_management_page.dart';
import '../pages/caregiver/insights_page.dart';
import '../pages/caregiver/profiles_page.dart';
import '../pages/caregiver/settings_page.dart';
import '../pages/caregiver/upload_content_page.dart';
import '../pages/child/audio_player_page.dart';
import '../pages/child/child_home_page.dart';
import '../pages/child/child_shell.dart';
import '../pages/child/story_library_page.dart';
import '../pages/shared/login_page.dart';

/* Centralised route table. To navigate from anywhere:
     Navigator.of(context).pushNamed(AppRoutes.uploadContent);
     AppNavigationService.pushNamed(AppRoutes.audioPlayer, arguments: {...}); */
class AppRoutes {
  AppRoutes._();

  // Top-level / auth
  static const String authGate = '/';
  static const String login = '/login';

  // Caregiver shells & pages
  static const String caregiverShell = '/caregiver';
  static const String caregiverDashboard = '/caregiver/dashboard';
  static const String profiles = '/caregiver/profiles';
  static const String contentManagement = '/caregiver/content';
  static const String uploadContent = '/caregiver/content/upload';
  static const String insights = '/caregiver/insights';
  static const String settings = '/caregiver/settings';

  // Child shells & pages
  static const String childShell = '/child';
  static const String childHome = '/child/home';
  static const String storyLibrary = '/child/stories';
  static const String audioPlayer = '/child/audio-player';

  // For static routes that need no arguments, we can use a simple routes table.
  static final Map<String, WidgetBuilder> staticRoutes = <String, WidgetBuilder>{
    login: (_) => const LoginPage(),
    caregiverShell: (_) => const CaregiverShell(),
    caregiverDashboard: (_) => const CaregiverDashboardPage(),
    profiles: (_) => const ProfilesPage(),
    contentManagement: (_) => const ContentManagementPage(),
    uploadContent: (_) => const UploadContentPage(),
    insights: (_) => const InsightsPage(),
    settings: (_) => const SettingsPage(),
    childShell: (_) => const ChildShell(),
    childHome: (_) => const ChildHomePage(),
    storyLibrary: (_) => const StoryLibraryPage(),
  };

  /* Routes that need typed arguments. Example:
     Navigator.pushNamed(context, AppRoutes.audioPlayer, arguments: {
       'title': book.title,
       'audiobookId': book.audiobookId,
     });
     */
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case audioPlayer:
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => AudioPlayerPage(
            title: (args?['title'] as String?) ?? 'Story',
            audiobookId: args?['audiobookId'] as String?,
          ),
        );
      default:
        return null; // Falls through to the routes table or unknown handler.
    }
  }
}
