import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../theme/app_colors.dart';
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

  // Menu bottom nav specs
  static const _tabs = <_TabSpec>[
    _TabSpec(Icons.home_outlined, 'caregiver.tab_dashboard', AppColors.primaryBlue),
    _TabSpec(Icons.people_outline, 'caregiver.tab_profiles', AppColors.primaryBlue),
    _TabSpec(Icons.upload_outlined, 'caregiver.tab_content', AppColors.softPeach),
    _TabSpec(Icons.bar_chart_outlined, 'caregiver.tab_insights', AppColors.softMint),
    _TabSpec(Icons.settings_outlined, 'caregiver.tab_settings', AppColors.softMint),
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
        return SettingsPage(onBack: backToDashboard);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _pageFor(_index)),
      bottomNavigationBar: _CaregiverBottomNav(
        tabs: _tabs,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
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

class _CaregiverBottomNav extends StatelessWidget {
  final List<_TabSpec> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _CaregiverBottomNav({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(tabs.length, (i) {
            final t = tabs[i];
            final selected = i == currentIndex;
            return Expanded(
              child: InkWell(
                onTap: () => onTap(i),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? t.highlight : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(t.icon, size: 22, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      // FittedBox shrinks long labels (like the Bahasa ones)
                      // to fit one line; short labels stay full size.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          context.tr(t.labelKey),
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
