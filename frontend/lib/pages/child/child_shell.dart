import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/profiles_state.dart';
import '../../state/settings_state.dart';
import '../../theme/app_colors.dart';
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
  static const _pianoTab = 2;
  // Acts on tap (asks for the PIN) instead of showing a page.
  static const _exitTab = 3;

  // Lets the taskbar ask the piano before leaving an unsaved recording.
  final _pianoKey = GlobalKey<PianoPageState>();
  // Guards against opening the PIN dialog twice (e.g. the Exit tab and the
  // back gesture both firing) - stacked dialogs left a black screen on exit.
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    // Load the active child's settings for Child Mode.
    final childId = context.read<ProfilesState>().activeProfile?.childId;
    if (childId != null) {
      context.read<SettingsState>().loadForChild(childId);
    }
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
      case 0:
        return const ChildHomePage();
      case 1:
        // Library's back arrow goes to Home - pop() can't, since it's a tab
        // body, not a pushed route.
        return StoryLibraryPage(onBack: () => setState(() => _index = 0));
      case _pianoTab:
        return PianoPage(key: _pianoKey);
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
      child: ShelfTabScaffold(
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
    );
  }
}
