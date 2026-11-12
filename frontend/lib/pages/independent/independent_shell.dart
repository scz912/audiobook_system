import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/auth_state.dart';
import '../../state/chat_state.dart';
import '../../state/friends_state.dart';
import '../../state/profiles_state.dart';
import '../../state/settings_state.dart';
import '../../widgets/guide.dart';
import '../../widgets/shelf_nav_bar.dart';
import '../caregiver/content_management_page.dart';
import '../caregiver/insights_page.dart';
import '../caregiver/settings_page.dart';
import '../caregiver/upload_content_page.dart';
import '../child/child_home_page.dart';
import '../child/story_library_page.dart';
import '../community/community_page.dart';
import '../piano/piano_page.dart';

/* The app for a teenager who uses it on their own: one account, everything
   in one taskbar - no caregiver side and no Child Mode to switch to.

   Behind it is a single child profile (made at sign-up) that stands for the
   teenager, so moods, listening history and reading settings work just as
   they do in Child Mode. */
class IndependentShell extends StatefulWidget {
  const IndependentShell({super.key});

  @override
  State<IndependentShell> createState() => _IndependentShellState();
}

class _IndependentShellState extends State<IndependentShell> {
  int _index = 0;
  static const _homeTab = 0;
  static const _storiesTab = 1;
  static const _communityTab = 4;
  static const _pianoTab = 5;

  // Lets the taskbar ask the piano before leaving an unsaved recording.
  final _pianoKey = GlobalKey<PianoPageState>();
  final _shelfKey = GlobalKey<ShelfTabScaffoldState>();
  final _moodKey = GlobalKey();
  final _paigeKey = GlobalKey();
  final _shelf = ValueNotifier(StoryShelf.linear);
  // Checks for friend requests and messages, for the Community tab's dot.
  Timer? _notificationTimer;

  // Same tour as a child's, plus the tabs a caregiver would have.
  late final GuideController _guide = GuideController(
    openTab: _selectTab,
    onFinish: _guideDone,
    steps: [
      const GuideStep('guide.tour_hi', tab: _homeTab),
      GuideStep('guide.ch_mood', tab: _homeTab, target: _moodKey, waitFor: GuideEvent.moodPicked),
      GuideStep('guide.ch_books',
          tab: _storiesTab, spotlightTab: true, onStart: () => _shelf.value = StoryShelf.linear),
      GuideStep('guide.ch_more_fun',
          tab: _storiesTab, onStart: () => _shelf.value = StoryShelf.interactive),
      GuideStep('guide.ch_quran', tab: _storiesTab, onStart: () => _shelf.value = StoryShelf.quran),
      const GuideStep('guide.in_create', tab: 2, spotlightTab: true),
      const GuideStep('guide.in_progress', tab: 3, spotlightTab: true),
      const GuideStep('guide.community', tab: _communityTab, spotlightTab: true),
      const GuideStep('guide.piano', tab: _pianoTab, spotlightTab: true, turned: true),
      const GuideStep('guide.settings', tab: 6, spotlightTab: true),
      const GuideStep('guide.in_done', tab: _homeTab, celebrate: true),
      GuideStep('guide.ch_always', tab: _homeTab, target: _paigeKey),
    ],
  );
  String? _guideKey;

  late final ProfilesState _profiles = context.read<ProfilesState>();
  String? _lastMood;
  bool _creatingProfile = false;

  @override
  void initState() {
    super.initState();
    final id = context.read<AuthState>().user?.caregiverId;
    if (id != null) {
      _guideKey = 'independent.$id';
      GuideMemory.isDone(_guideKey!).then((done) {
        if (!done && mounted) _guide.start();
      });
    }
    _lastMood = _profiles.currentMood;
    _profiles.addListener(_onProfilesChanged);
    _onProfilesChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkNotifications());
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkNotifications(),
    );
  }

  @override
  void dispose() {
    _profiles.removeListener(_onProfilesChanged);
    _notificationTimer?.cancel();
    _guide.dispose();
    _shelf.dispose();
    super.dispose();
  }

  void _onProfilesChanged() {
    /* Their profile is made at sign-up. If it's missing (say the account
       was made before personal accounts existed), make it now rather than
       ever asking them to add a child. */
    if (_profiles.hasLoaded && _profiles.profiles.isEmpty && !_creatingProfile) {
      _creatingProfile = true;
      final name = context.read<AuthState>().user?.name ?? '';
      scheduleMicrotask(() => _profiles.addProfile(
            name: name.isEmpty ? 'Me' : name,
            age: 13,
            avatarEmoji: '🌟',
            avatarColorHex: '#F5D5DD',
          ));
    }
    // The teenager is the listener: use their profile as soon as it loads.
    if (_profiles.activeProfile == null && _profiles.profiles.isNotEmpty) {
      final me = _profiles.profiles.first;
      // Not during a build: entering notifies listeners.
      scheduleMicrotask(() {
        if (!mounted || _profiles.activeProfile != null) return;
        _profiles.enterChildMode(me);
        context.read<SettingsState>().loadForChild(me.childId);
      });
    }
    // A mood picked on Home moves the guide on.
    final mood = _profiles.currentMood;
    if (mood != null && mood != _lastMood) _guide.report(GuideEvent.moodPicked);
    _lastMood = mood;
  }

  void _checkNotifications() {
    if (!mounted) return;
    context.read<FriendsState>().refreshNotifications();
    context.read<ChatState>().refreshQuietly();
  }

  void _guideDone() {
    final key = _guideKey;
    if (key != null) GuideMemory.markDone(key);
  }

  static const _tabs = <(IconData, String, Color)>[
    (Icons.home_outlined, 'child.tab_home', Color(0xFFA9C5E8)), // sky blue
    (Icons.menu_book_outlined, 'child.tab_stories', Color(0xFFA9DBB8)), // mint
    (Icons.auto_awesome_outlined, 'independent.tab_create', Color(0xFFF3DC8A)), // butter yellow
    (Icons.bar_chart_outlined, 'independent.tab_progress', Color(0xFFF5BE96)), // apricot
    (Icons.diversity_3_outlined, 'caregiver.tab_community', Color(0xFFC9B6EC)), // lavender
    (Icons.piano_outlined, 'caregiver.tab_piano', Color(0xFFF2B3CB)), // pink
    (Icons.settings_outlined, 'caregiver.tab_settings', Color(0xFF9ED8DB)), // teal
  ];

  Widget _pageFor(int i) {
    void backHome() => setState(() => _index = _homeTab);
    switch (i) {
      case _homeTab:
        return ChildHomePage(
          moodCardKey: _moodKey,
          paigeKey: _paigeKey,
          onPaigeTap: _guide.start,
          showTopBooks: true,
        );
      case _storiesTab:
        return StoryLibraryPage(
          onBack: backHome,
          shelf: _shelf,
          onCreate: (format) => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => UploadContentPage(interactive: format == StoryShelf.interactive),
          )),
        );
      case 2:
        return ContentManagementPage(onBack: backHome);
      case 3:
        return const InsightsPage(showMusicTaste: true);
      case _communityTab:
        return const CommunityPage();
      case _pianoTab:
        return AboveShelf(
          child: PianoPage(key: _pianoKey, onGuideEvent: _guide.report),
        );
      case 6:
        return SettingsPage(onBack: backHome);
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
    final profiles = context.watch<ProfilesState>();
    // Wait for their profile, so Home and the player know who's listening.
    if (profiles.activeProfile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ShelfTabScaffold(
          key: _shelfKey,
          body: _pageFor(_index),
          items: [
            for (var i = 0; i < _tabs.length; i++)
              ShelfNavItem(
                icon: _tabs[i].$1,
                label: context.tr(_tabs[i].$2),
                color: _tabs[i].$3,
                dot: i == _communityTab &&
                    (context.watch<FriendsState>().hasNotification ||
                        context.watch<ChatState>().hasUnmutedUnread),
              ),
          ],
          currentIndex: _index,
          rotateItems: _index == _pianoTab,
          onTap: _selectTab,
        ),
        ListenableBuilder(
          listenable: _guide,
          builder: (context, _) => _guide.active
              ? GuideOverlay(
                  controller: _guide,
                  tabRect: (i) => _shelfKey.currentState?.sphereRect(i),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
