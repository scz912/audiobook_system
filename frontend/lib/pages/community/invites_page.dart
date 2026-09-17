import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/community/community_invite.dart';
import '../../state/community_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/soft_card.dart';

// Create and view invite codes to bring other families into the private hub.
class InvitesPage extends StatefulWidget {
  const InvitesPage({super.key});

  @override
  State<InvitesPage> createState() => _InvitesPageState();
}

class _InvitesPageState extends State<InvitesPage> {
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CommunityState>().loadInvites();
    });
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    final invite = await context.read<CommunityState>().createInvite();
    if (!mounted) return;
    setState(() => _creating = false);
    if (invite != null) {
      AppSnackbar.success('Invite code created', context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final community = context.watch<CommunityState>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  BackPill(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 12),
                  const Text('Invite families',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  const Text(
                    'Share a code with another family of an autistic child. '
                    'Only people with a code can join — the hub never goes public.',
                    style: TextStyle(color: AppColors.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _creating ? null : _create,
                      icon: _creating
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_rounded),
                      label: const Text('Create a new code',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (community.invites.isNotEmpty)
                    const Text('Your codes',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  ...community.invites.map((i) => _InviteTile(invite: i)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  final CommunityInvite invite;
  const _InviteTile({required this.invite});

  @override
  Widget build(BuildContext context) {
    final used = invite.status != 'pending';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(invite.code,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2)),
                  const SizedBox(height: 2),
                  Text(used ? 'Used' : 'Waiting to be used',
                      style: TextStyle(
                          color: used ? AppColors.textMuted : AppColors.success,
                          fontSize: 12)),
                ],
              ),
            ),
            if (!used)
              IconButton(
                icon: const Icon(Icons.copy_rounded,
                    color: AppColors.primaryBlueDark),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: invite.code));
                  AppSnackbar.success('Code copied', context: context);
                },
              ),
          ],
        ),
      ),
    );
  }
}
