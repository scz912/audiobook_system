import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/chat_state.dart';
import '../../state/community_state.dart';
import '../../state/friends_state.dart';
import '../../state/hub_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/soft_card.dart';
import 'chat_tab.dart';
import 'friends_tab.dart';
import 'hub_tab.dart';
import 'invites_page.dart';

/* The Community tab. Shows a join gate until the caregiver is a member, then
   three inner tabs: Hub, Chat, and Friends. */
class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final community = context.read<CommunityState>();
      if (!community.checked) community.refreshStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final community = context.watch<CommunityState>();

    if (!community.checked || community.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!community.isMember) {
      return const _JoinGate();
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                const Text(
                  'Community',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Invite a family',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const InvitesPage()),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                ),
              ],
            ),
          ),
          const TabBar(
            labelColor: AppColors.primaryBlueDark,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primaryBlueDark,
            tabs: [
              Tab(text: 'Hub'),
              Tab(text: 'Chat'),
              Tab(text: 'Friends'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                HubTab(),
                ChatTab(),
                FriendsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Shown before the caregiver joins — explains the private, invite-only hub.
class _JoinGate extends StatefulWidget {
  const _JoinGate();

  @override
  State<_JoinGate> createState() => _JoinGateState();
}

class _JoinGateState extends State<_JoinGate> {
  final _codeCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join({String? code}) async {
    setState(() => _busy = true);
    final community = context.read<CommunityState>();
    final ok = code != null && code.isNotEmpty
        ? await community.acceptInvite(code)
        : await community.join();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _loadAll();
      AppSnackbar.success('Welcome to the community!', context: context);
    } else {
      AppSnackbar.error(community.lastError ?? 'Could not join', context: context);
    }
  }

  void _loadAll() {
    context.read<HubState>().refresh();
    context.read<ChatState>().refresh();
    context.read<FriendsState>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: AppColors.iconCirclePurple,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.diversity_3_rounded,
                size: 46, color: AppColors.primaryBlueDark),
          ),
          const SizedBox(height: 18),
          const Text(
            'A private space for families',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          const Text(
            'Connect with other families, chat, and share the stories you '
            'create. This community is private and invite-only — nothing here '
            'is ever public.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _busy ? null : () => _join(),
              child: _busy
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Join the community',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 20),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Have an invite code?',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'Enter code'),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => _join(code: _codeCtrl.text.trim().toUpperCase()),
                    child: const Text('Redeem code'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
