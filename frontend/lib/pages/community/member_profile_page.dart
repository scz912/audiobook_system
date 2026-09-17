import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/community/member.dart';
import '../../services/database_service.dart';
import '../../state/friends_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/soft_card.dart';
import 'chat_thread_page.dart';
import 'community_widgets.dart';

// A member's profile: avatar, bio, shared count, and add-friend / message actions.
class MemberProfilePage extends StatefulWidget {
  final String caregiverId;
  const MemberProfilePage({super.key, required this.caregiverId});

  @override
  State<MemberProfilePage> createState() => _MemberProfilePageState();
}

class _MemberProfilePageState extends State<MemberProfilePage> {
  Member? _member;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final resp = await DatabaseService.memberProfile(widget.caregiverId);
    if (!mounted) return;
    setState(() {
      _member = resp.success && resp.data is Member ? resp.data as Member : null;
      _loading = false;
    });
  }

  Future<void> _addFriend() async {
    setState(() => _busy = true);
    final ok = await context.read<FriendsState>().sendRequest(widget.caregiverId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      AppSnackbar.success('Request sent', context: context);
      _load();
    }
  }

  Future<void> _message() async {
    setState(() => _busy = true);
    final resp = await DatabaseService.startDirectChat(widget.caregiverId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (resp.success && resp.data != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatThreadPage(conversation: resp.data),
      ));
    } else {
      AppSnackbar.error(resp.message, context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  const Text('Profile',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _member == null
                      ? const Center(
                          child: Text('Could not load this profile',
                              style: TextStyle(color: AppColors.textSecondary)))
                      : _body(_member!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(Member member) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const SizedBox(height: 12),
        Center(
          child: MemberAvatar(
            emoji: member.avatarEmoji,
            colorHex: member.avatarColor,
            size: 96,
          ),
        ),
        const SizedBox(height: 14),
        Text(member.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        if (member.bio != null && member.bio!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(member.bio!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4)),
        ],
        const SizedBox(height: 16),
        SoftCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Stat(value: '${member.sharedCount}', label: 'Shared stories'),
              Container(width: 1, height: 34, color: AppColors.cardBorder),
              _Stat(
                value: member.relation == 'friends' ? 'Friends' : '—',
                label: 'Status',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _friendButton(member)),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  side: const BorderSide(color: AppColors.cardBorder),
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _busy ? null : _message,
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Message'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _friendButton(Member member) {
    if (member.relation == 'friends') {
      return FilledButton.icon(
        style: _filledStyle(AppColors.softMintDark),
        onPressed: null,
        icon: const Icon(Icons.people_rounded),
        label: const Text('Friends'),
      );
    }
    if (member.relation == 'request_sent') {
      return FilledButton.icon(
        style: _filledStyle(AppColors.cardBorder),
        onPressed: null,
        icon: const Icon(Icons.hourglass_top_rounded),
        label: const Text('Requested'),
      );
    }
    return FilledButton.icon(
      style: _filledStyle(AppColors.primaryBlue),
      onPressed: _busy ? null : _addFriend,
      icon: const Icon(Icons.person_add_alt_1_rounded),
      label: const Text('Add friend'),
    );
  }

  ButtonStyle _filledStyle(Color color) => FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}
