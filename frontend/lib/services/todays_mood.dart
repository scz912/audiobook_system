import 'package:shared_preferences/shared_preferences.dart';

import '../state/profiles_state.dart';

/* Today's mood for [childId]: picked this session, or saved on the home
   page today (key mood_<childId>_<yyyy-mm-dd>). Null if none. Used to
   suit recommendations to how they feel. */
Future<String?> todaysMood(ProfilesState profiles, String childId) async {
  if (profiles.activeProfile?.childId == childId && profiles.currentMood != null) {
    return profiles.currentMood;
  }
  final now = DateTime.now();
  final ymd = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  try {
    return (await SharedPreferences.getInstance()).getString('mood_${childId}_$ymd');
  } catch (_) {
    return null;
  }
}
