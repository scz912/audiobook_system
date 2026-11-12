import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/child_profile.dart';
import '../../state/profiles_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/adaptive_row.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/soft_card.dart';
import '../child/child_shell.dart';
import '../../widgets/shelf_nav_bar.dart';
import 'add_child_dialog.dart';
import 'child_profile_actions.dart';
import '../../widgets/whole_words_text.dart';

class ProfilesPage extends StatelessWidget {
  const ProfilesPage({super.key});

  void _enterChildMode(BuildContext context, ChildProfile profile) {
    context.read<ProfilesState>().enterChildMode(profile);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ChildShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profiles = context.watch<ProfilesState>().profiles;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, shelfBottomSpace(context)),
      children: [
        AdaptiveRow(
          body: WholeWordsText(
            context.tr('profiles.title'),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          trailing: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: AppColors.textPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.tr('profiles.add_child')),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const AddChildDialog(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (profiles.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: EmptyState(
              icon: Icons.child_care_rounded,
              title: context.tr('caregiver.no_children'),
              subtitle: context.tr('profiles.empty_subtitle'),
              action: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.tr('profiles.add_child')),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const AddChildDialog(),
                ),
              ),
            ),
          )
        else
          for (final p in profiles) ...[
          SoftCard(
            // On a narrow screen the buttons drop under the details.
            child: AdaptiveRow(
              leading: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: p.avatarColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(p.avatarEmoji, style: const TextStyle(fontSize: 28)),
              ),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                      '${context.tr('caregiver.age')} ${p.age} • ${p.favoriteGenre}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                      '${p.listeningMinutes} ${context.tr('profiles.minutes_listened')}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
              trailing: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => _enterChildMode(context, p),
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: AppColors.textPrimary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(context.tr('profiles.enter'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  ChildProfileActionIcons(profile: p),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
