import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(
              children: [
                Text(
                  context.tr('community.title'),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.softLavender,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const InvitesPage()),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: Text(context.tr('community.invite'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          TabBar(
            labelColor: AppColors.primaryBlueDark,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primaryBlueDark,
            tabs: [
              Tab(text: context.tr('community.hub')),
              Tab(text: context.tr('community.chat')),
              Tab(text: context.tr('community.friends')),
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

// Shown before the caregiver joins - explains the private, invite-only hub.
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
      AppSnackbar.success(context.trRead('community.welcome'), context: context);
    } else {
      AppSnackbar.error(
          community.lastError ?? context.trRead('community.join_failed'),
          context: context);
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
          Text(
            context.tr('community.join_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            context.tr('community.join_body'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
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
                  : Text(context.tr('community.join_button'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 20),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('community.have_code'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                      hintText: context.tr('community.enter_code')),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => _join(code: _codeCtrl.text.trim().toUpperCase()),
                    child: Text(context.tr('community.redeem')),
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
