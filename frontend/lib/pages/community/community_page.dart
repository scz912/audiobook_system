import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/chat_state.dart';
import '../../state/community_state.dart';
import '../../state/friends_state.dart';
import '../../state/hub_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/notification_dot.dart';
import '../../widgets/soft_card.dart';
import '../../widgets/shelf_nav_bar.dart';
import '../../widgets/whole_words_text.dart';
import 'chat_tab.dart';
import 'community_widgets.dart';
import 'friends_tab.dart';
import 'hub_tab.dart';
import 'invites_page.dart';
import 'meet_families_page.dart';

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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: WholeWordsText(
                    context.tr('community.title'),
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w900, color: communityInk),
                  ),
                ),
                // Invite someone: a big round yellow button.
                Tooltip(
                  message: context.tr('community.invite'),
                  child: Material(
                    color: communitySun,
                    shape: const CircleBorder(
                        side: BorderSide(color: communityInk, width: 2.5)),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const InvitesPage()),
                      ),
                      child: const SizedBox(
                        width: 56,
                        height: 56,
                        child: Icon(Icons.person_add_alt_1_rounded,
                            size: 30, color: communityInk),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _CommunityTabs(
            chatDot: context.watch<ChatState>().hasUnmutedUnread,
            friendsDot: context.watch<FriendsState>().hasNotification,
          ),
          const SizedBox(height: 6),
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

/* Hub, Chat and Friends as three big coloured buttons with an icon each,
   instead of thin text tabs. A red dot marks unread chats or new friend
   news. */
class _CommunityTabs extends StatelessWidget {
  final bool chatDot;
  final bool friendsDot;
  const _CommunityTabs({required this.chatDot, required this.friendsDot});

  static const _tabs = [
    (Icons.auto_stories_rounded, 'community.hub', Color(0xFFFFC83D)),
    (Icons.forum_rounded, 'community.chat', Color(0xFF8EC9F5)),
    (Icons.people_alt_rounded, 'community.friends', Color(0xFF9EDDB0)),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _tab(context, i, controller.index == i,
                    i == 1 ? chatDot : (i == 2 ? friendsDot : false),
                    () => controller.animateTo(i)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int i, bool selected, bool dot, VoidCallback onTap) {
    final (icon, key, color) = _tabs[i];
    return Semantics(
      button: true,
      selected: selected,
      label: context.tr(key),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: communityInk, width: selected ? 3 : 2),
            boxShadow: selected
                ? [BoxShadow(color: communityInk.withValues(alpha: 0.25), offset: const Offset(0, 4))]
                : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 28, color: communityInk),
                      const SizedBox(width: 6),
                      ExcludeSemantics(
                        child: Text(
                          context.tr(key),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900, color: communityInk),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (dot) const Positioned(top: 4, right: 0, child: NotificationDot()),
            ],
          ),
        ),
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
      // Show who's already here, so they can send friend requests.
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MeetFamiliesPage()),
      );
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
      padding: EdgeInsets.fromLTRB(24, 24, 24, shelfBottomSpace(context)),
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
