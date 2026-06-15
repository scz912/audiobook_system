import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/child_profile.dart';
import '../../navigation/app_navigation_service.dart';
import '../../state/auth_state.dart';
import '../../state/profiles_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/soft_card.dart';
import '../../widgets/stat_card.dart';
import '../shared/auth_gate.dart';
import '../child/child_shell.dart';
import 'add_child_dialog.dart';
import 'child_profile_actions.dart';

class CaregiverDashboardPage extends StatelessWidget {
  final ValueChanged<int>? onJumpToTab;
  const CaregiverDashboardPage({super.key, this.onJumpToTab});

  void _enterChildMode(BuildContext context, ChildProfile profile) {
    context.read<ProfilesState>().enterChildMode(profile);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ChildShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profiles = context.watch<ProfilesState>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('caregiver.dashboard'),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const _LogoutDialog(),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(context.tr('caregiver.logout')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          context.tr('caregiver.dashboard_subtitle'),
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),

        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          // Just shy of square — fits the two-line labels with no gap below.
          childAspectRatio: 1.05,
          children: [
            StatCard(
              icon: Icons.people_outline,
              iconBackground: AppColors.iconCircleBlue,
              value: '${profiles.totalChildren}',
              label: context.tr('caregiver.stat_total_children'),
            ),
            StatCard(
              icon: Icons.access_time,
              iconBackground: AppColors.iconCircleGreen,
              value: '${profiles.totalListeningMinutes}',
              label: context.tr('caregiver.stat_total_minutes'),
            ),
            StatCard(
              icon: Icons.menu_book_outlined,
              iconBackground: AppColors.iconCirclePeach,
              value: '6',
              label: context.tr('caregiver.stat_total_books'),
            ),
            StatCard(
              icon: Icons.psychology_outlined,
              iconBackground: AppColors.iconCirclePurple,
              value: '${profiles.averageEngagement}%',
              label: context.tr('caregiver.stat_avg_engagement'),
            ),
          ],
        ),

        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('caregiver.section_profiles'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const AddChildDialog(),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.tr('profiles.add_child')),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (profiles.profiles.isEmpty)
          EmptyState(
            icon: Icons.child_care_rounded,
            title: context.tr('caregiver.no_children'),
            subtitle: context.tr('caregiver.empty_subtitle'),
            iconBackground: AppColors.iconCircleBlue,
            iconColor: AppColors.primaryBlueDark,
            action: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const AddChildDialog(),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.tr('caregiver.add_first_child')),
            ),
          )
        else
          for (final profile in profiles.profiles) ...[
            _ChildProfileCard(
              profile: profile,
              onEnterChildMode: () => _enterChildMode(context, profile),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _ChildProfileCard extends StatelessWidget {
  final ChildProfile profile;
  final VoidCallback onEnterChildMode;
  const _ChildProfileCard({required this.profile, required this.onEnterChildMode});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: profile.avatarColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(profile.avatarEmoji, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${context.tr('caregiver.age')} ${profile.age}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              ChildProfileActionIcons(profile: profile),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('caregiver.listening_time'),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                ),
              ),
              Text(
                '${profile.listeningMinutes} ${context.tr('caregiver.minutes_short')}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('caregiver.favorite_genre'),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                ),
              ),
              Text(
                profile.favoriteGenre ?? '—',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onEnterChildMode,
              style: OutlinedButton.styleFrom(
                backgroundColor: AppColors.background,
                side: const BorderSide(color: AppColors.cardBorder),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                context.tr('caregiver.enter_child_mode'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoutDialog extends StatelessWidget {
  const _LogoutDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(context.tr('caregiver.logout_title')),
      content: Text(context.tr('caregiver.logout_body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('common.cancel')),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
          ),
          onPressed: () async {
            // Grab these before popping the dialog so we don't use a dead
            // context after the await.
            final auth = context.read<AuthState>();
            final navigator = AppNavigationService.navigatorKey.currentState;
            Navigator.pop(context);
            await auth.logout();
            // Child Mode swaps out AuthGate, so reset the stack to a fresh
            // one — now signed out, it shows the LoginPage.
            navigator?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthGate()),
              (route) => false,
            );
          },
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: Text(context.tr('caregiver.logout'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
