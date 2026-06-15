import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/profiles_state.dart';
import '../../state/settings_state.dart';
import '../../theme/app_colors.dart';
import '../caregiver/caregiver_shell.dart';
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
    final ok = await showGuardianPinDialog(context);
    if (!ok || !mounted) return;
    context.read<ProfilesState>().exitChildMode();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CaregiverShell()),
    );
  }

  Widget _pageFor(int i) {
    switch (i) {
      case 0:
        return const ChildHomePage();
      case 1:
        // Library's back arrow goes to Home — pop() can't, since it's a tab
        // body, not a pushed route.
        return StoryLibraryPage(onBack: () => setState(() => _index = 0));
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _attemptExit();
      },
      child: Scaffold(
        body: SafeArea(child: _pageFor(_index)),
        bottomNavigationBar: _ChildBottomNav(
          currentIndex: _index,
          onTap: (i) {
            if (i == 2) {
              _attemptExit();
            } else {
              setState(() => _index = i);
            }
          },
        ),
      ),
    );
  }
}

class _ChildBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _ChildBottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (icon: Icons.home_outlined, label: context.tr('child.tab_home'), color: AppColors.primaryBlue),
      (icon: Icons.menu_book_outlined, label: context.tr('child.tab_stories'), color: AppColors.softMint),
      (icon: Icons.logout, label: context.tr('child.tab_exit'), color: AppColors.softPeach),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(tabs.length, (i) {
            final t = tabs[i];
            final selected = i == currentIndex && i != 2;
            return Expanded(
              child: InkWell(
                onTap: () => onTap(i),
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? t.color : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(t.icon, size: 24, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          t.label,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
