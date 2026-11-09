import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/profiles_state.dart';
import '../../state/settings_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/guide.dart';
import '../../widgets/shelf_nav_bar.dart';
import '../caregiver/caregiver_shell.dart';
import '../piano/piano_page.dart';
import '../shared/guardian_pin_dialog.dart';
import 'child_home_page.dart';
import 'story_library_page.dart';

class ChildShell extends StatefulWidget {
  const ChildShell({super.key});

  @override
  State<ChildShell> createState() => _ChildShellState();
}

class _ChildShellState extends State<ChildShell> {
  int _index = 0;
  static const _homeTab = 0;
  static const _storiesTab = 1;
  static const _pianoTab = 2;
  // Acts on tap (asks for the PIN) instead of showing a page.
  static const _exitTab = 3;

  // Lets the taskbar ask the piano before leaving an unsaved recording.
  final _pianoKey = GlobalKey<PianoPageState>();
  // Guards against opening the PIN dialog twice (e.g. the Exit tab and the
  // back gesture both firing) - stacked dialogs left a black screen on exit.
  bool _exiting = false;

  // What the guide points at.
  final _shelfKey = GlobalKey<ShelfTabScaffoldState>();
  final _moodKey = GlobalKey();
  final _paigeKey = GlobalKey();
  final _recordKey = GlobalKey();
  final _stopKey = GlobalKey();
  final _keyboardKey = GlobalKey();
  final _saveKey = GlobalKey();
  final _shelf = ValueNotifier(StoryShelf.linear);

  /* The child's guide, learned by doing: pick a mood, see the books, then
     play the piano, record, listen back and name the song. Shown the first
     time each child uses Child Mode; Paige on Home replays it. */
  late final GuideController _guide = GuideController(
    openTab: _selectTab,
    onFinish: _guideDone,
    steps: [
      const GuideStep('guide.ch_hi', tab: _homeTab),
      GuideStep('guide.ch_mood', tab: _homeTab, target: _moodKey, waitFor: GuideEvent.moodPicked),
      GuideStep('guide.ch_books',
          tab: _storiesTab, spotlightTab: true, onStart: () => _shelf.value = StoryShelf.linear),
      GuideStep('guide.ch_more_fun',
          tab: _storiesTab, onStart: () => _shelf.value = StoryShelf.interactive),
      GuideStep('guide.ch_quran', tab: _storiesTab, onStart: () => _shelf.value = StoryShelf.quran),
      const GuideStep('guide.ch_piano', tab: _pianoTab, spotlightTab: true, turned: true),
      GuideStep('guide.ch_tap_note',
          tab: _pianoTab, target: _keyboardKey, waitFor: GuideEvent.notePlayed, turned: true),
      GuideStep('guide.ch_record',
          tab: _pianoTab, target: _recordKey, waitFor: GuideEvent.recordingStarted, turned: true),
      GuideStep('guide.ch_stop',
          tab: _pianoTab, target: _stopKey, waitFor: GuideEvent.recordingStopped, turned: true),
      const GuideStep('guide.ch_listen', tab: _pianoTab, turned: true),
      GuideStep('guide.ch_name',
          tab: _pianoTab, target: _saveKey, waitFor: GuideEvent.recordingSaved, turned: true),
      const GuideStep('guide.ch_yay', tab: _pianoTab, celebrate: true, turned: true),
      GuideStep('guide.ch_always', tab: _homeTab, target: _paigeKey),
    ],
  );
  String? _guideKey;

  late final ProfilesState _profiles = context.read<ProfilesState>();
  String? _lastMood;

  @override
  void initState() {
    super.initState();
    // Load the active child's settings for Child Mode.
    final childId = _profiles.activeProfile?.childId;
    if (childId != null) {
      // After the first frame: loading notifies listeners, which isn't
      // allowed while the shell itself is being built.
      final settings = context.read<SettingsState>();
      WidgetsBinding.instance.addPostFrameCallback((_) => settings.loadForChild(childId));
      _guideKey = 'child.$childId';
      GuideMemory.isDone(_guideKey!).then((done) {
        if (!done && mounted) _guide.start();
      });
    }
    _lastMood = _profiles.currentMood;
    _profiles.addListener(_onProfilesChanged);
  }

  @override
  void dispose() {
    _profiles.removeListener(_onProfilesChanged);
    _guide.dispose();
    _shelf.dispose();
    super.dispose();
  }

  // A mood picked on Home moves the guide on.
  void _onProfilesChanged() {
    final mood = _profiles.currentMood;
    if (mood != null && mood != _lastMood) _guide.report(GuideEvent.moodPicked);
    _lastMood = mood;
  }

  void _guideDone() {
    final key = _guideKey;
    if (key != null) GuideMemory.markDone(key);
  }

  Future<void> _attemptExit() async {
    if (_exiting) return;
    _exiting = true;
    try {
      final ok = await showGuardianPinDialog(context);
      if (!ok || !mounted) return;
      context.read<ProfilesState>().exitChildMode();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CaregiverShell()),
      );
    } finally {
      _exiting = false;
    }
  }

  Widget _pageFor(int i) {
    switch (i) {
      case _homeTab:
        return ChildHomePage(
          moodCardKey: _moodKey,
          paigeKey: _paigeKey,
          onPaigeTap: _guide.start,
        );
      case _storiesTab:
        // Library's back arrow goes to Home - pop() can't, since it's a tab
        // body, not a pushed route.
        return StoryLibraryPage(
          onBack: () => setState(() => _index = _homeTab),
          shelf: _shelf,
        );
      case _pianoTab:
        return AboveShelf(
          child: PianoPage(
            key: _pianoKey,
            onGuideEvent: _guide.report,
            recordButtonKey: _recordKey,
            stopButtonKey: _stopKey,
            keyboardKey: _keyboardKey,
            saveButtonKey: _saveKey,
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _selectTab(int i) async {
    if (i == _index) return;
    // Ask before an unsaved piano recording is lost.
    if (_index == _pianoTab &&
        !(await _pianoKey.currentState?.confirmLeave() ?? true)) {
      return;
    }
    if (!mounted) return;
    if (i == _exitTab) {
      _attemptExit();
    } else {
      setState(() => _index = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _attemptExit();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ShelfTabScaffold(
            key: _shelfKey,
            body: _pageFor(_index),
            items: [
              ShelfNavItem(icon: Icons.home_outlined, label: context.tr('child.tab_home'), color: AppColors.primaryBlue),
              ShelfNavItem(icon: Icons.menu_book_outlined, label: context.tr('child.tab_stories'), color: AppColors.softMint),
              ShelfNavItem(icon: Icons.piano_outlined, label: context.tr('child.tab_piano'), color: AppColors.softPink),
              ShelfNavItem(icon: Icons.logout, label: context.tr('child.tab_exit'), color: AppColors.softPeach),
            ],
            currentIndex: _index,
            // The piano is drawn sideways, so the icons turn with it.
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
      ),
    );
  }
}
