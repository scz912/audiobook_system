import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/child_profile.dart';
import '../../state/profiles_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import 'add_child_dialog.dart';

/* Shared edit + remove actions for a child profile, used by both the
   Caregiver Dashboard and the Profiles page. Centralising the dialogs here
   means the confirmation copy and snackbar handling stay consistent. */
class ChildProfileActions {
  ChildProfileActions._();

  /* Open the AddChildDialog in edit mode for [profile]. Resolves when the
     dialog closes; the caller doesn't need the result because
     [ProfilesState] is already notified by the dialog. */
  static Future<void> openEdit(BuildContext context, ChildProfile profile) {
    return showDialog(
      context: context,
      builder: (_) => AddChildDialog(existing: profile),
    );
  }

  /* Ask "are you sure?", then delete on confirm. Surfaces an error snackbar
     if the backend rejects the delete. */
  static Future<void> confirmRemove(
      BuildContext context, ChildProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(ctx.tr('profiles.remove_confirm')),
        content: Text(
          ctx.tr('profiles.remove_confirm_body'),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('profiles.remove_button')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final profiles = context.read<ProfilesState>();
    final ok = await profiles.deleteProfile(profile.childId);
    if (!context.mounted) return;
    if (!ok) {
      AppSnackbar.error(
        profiles.lastError ?? 'Could not remove profile',
        context: context,
      );
    }
  }
}

/* Edit + Delete icon pair, sized to live in the trailing slot of a child
   profile card. Tapping each fires the shared dialog flow. */
class ChildProfileActionIcons extends StatelessWidget {
  final ChildProfile profile;
  const ChildProfileActionIcons({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionIcon(
          icon: Icons.edit_rounded,
          background: AppColors.iconCircleBlue,
          tooltip: context.tr('profiles.edit_label'),
          onTap: () => ChildProfileActions.openEdit(context, profile),
        ),
        const SizedBox(width: 8),
        _ActionIcon(
          icon: Icons.delete_outline_rounded,
          background: AppColors.softPeach,
          foreground: AppColors.danger,
          tooltip: context.tr('profiles.remove_label'),
          onTap: () => ChildProfileActions.confirmRemove(context, profile),
        ),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color? foreground;
  final String tooltip;
  final VoidCallback onTap;
  const _ActionIcon({
    required this.icon,
    required this.background,
    required this.tooltip,
    required this.onTap,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: foreground ?? AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
