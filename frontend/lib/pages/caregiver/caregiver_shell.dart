import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/chat_state.dart';
import '../../state/friends_state.dart';
import '../../widgets/shelf_nav_bar.dart';
import '../community/community_page.dart';
import '../piano/piano_page.dart';
import 'caregiver_dashboard_page.dart';
import 'content_management_page.dart';
import 'insights_page.dart';
import 'profiles_page.dart';
import 'settings_page.dart';

class CaregiverShell extends StatefulWidget {
  final int initialIndex;
  const CaregiverShell({super.key, this.initialIndex = 0});

  @override
  State<CaregiverShell> createState() => _CaregiverShellState();
}

class _CaregiverShellState extends State<CaregiverShell> {
  late int _index = widget.initialIndex;
  // Checks for friend requests and answers, for the Community tab's dot.
  Timer? _notificationTimer;

  static const _communityTab = 4;
  static const _pianoTab = 5;
  // Lets the taskbar ask the piano before leaving an unsaved recording.
  final _pianoKey = GlobalKey<PianoPageState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkNotifications());
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkNotifications(),
    );
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    super.dispose();
  }

  // Friend requests and unread messages (muted chats excluded) drive the dot.
  void _checkNotifications() {
    if (!mounted) return;
    context.read<FriendsState>().refreshNotifications();
    context.read<ChatState>().refreshQuietly();
  }

  /* Taskbar tabs. Each has its own hue, spread round the colour wheel,
     since it also dyes the page background - pages should be easy to
     tell apart at a glance. */
  static const _tabs = <_TabSpec>[
    _TabSpec(Icons.home_outlined, 'caregiver.tab_dashboard', Color(0xFFA9C5E8)), // sky blue
    _TabSpec(Icons.people_outline, 'caregiver.tab_profiles', Color(0xFFF5BE96)), // apricot
    _TabSpec(Icons.upload_outlined, 'caregiver.tab_content', Color(0xFFF3DC8A)), // butter yellow
    _TabSpec(Icons.bar_chart_outlined, 'caregiver.tab_insights', Color(0xFFA9DBB8)), // mint
    _TabSpec(Icons.diversity_3_outlined, 'caregiver.tab_community', Color(0xFFC9B6EC)), // lavender
    _TabSpec(Icons.piano_outlined, 'caregiver.tab_piano', Color(0xFFF2B3CB)), // pink
    _TabSpec(Icons.settings_outlined, 'caregiver.tab_settings', Color(0xFF9ED8DB)), // teal
  ];

  Widget _pageFor(int i) {
    // Back arrow means go back to caregiver dashboard 
    void backToDashboard() => setState(() => _index = 0);
    switch (i) {
      case 0:
        return CaregiverDashboardPage(onJumpToTab: (idx) => setState(() => _index = idx));
      case 1:
        return const ProfilesPage();
      case 2:
        return ContentManagementPage(onBack: backToDashboard);
      case 3:
        return const InsightsPage();
      case 4:
        return const CommunityPage();
      case 5:
        return PianoPage(key: _pianoKey);
      case 6:
        return SettingsPage(onBack: backToDashboard);
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _selectTab(int i) async {
    if (i == _index) return;
    if (_index == _pianoTab &&
        !(await _pianoKey.currentState?.confirmLeave() ?? true)) {
      return;
    }
    if (mounted) setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return ShelfTabScaffold(
      body: _pageFor(_index),
      items: [
        for (var i = 0; i < _tabs.length; i++)
          ShelfNavItem(
            icon: _tabs[i].icon,
            label: context.tr(_tabs[i].labelKey),
            color: _tabs[i].highlight,
            dot: i == _communityTab &&
                (context.watch<FriendsState>().hasNotification ||
                    context.watch<ChatState>().hasUnmutedUnread),
          ),
      ],
      currentIndex: _index,
      // The piano is drawn sideways, so the icons turn with it.
      rotateItems: _index == _pianoTab,
      onTap: _selectTab,
    );
  }
}

class _TabSpec {
  final IconData icon;
  // Translation key (e.g. 'caregiver.tab_dashboard'), resolved when shown.
  final String labelKey;
  final Color highlight;
  const _TabSpec(this.icon, this.labelKey, this.highlight);
}
