import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/community/friend_update.dart';
import '../../models/community/member.dart';
import '../../state/friends_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/shelf_nav_bar.dart';
import 'community_widgets.dart';
import 'member_profile_page.dart';

// Friends list, incoming requests, and member search.
class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key});

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  final _searchCtrl = TextEditingController();
  bool _searchMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FriendsState>().refresh();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _runSearch(String term) {
    final trimmed = term.trim();
    setState(() => _searchMode = trimmed.isNotEmpty);
    if (trimmed.isNotEmpty) {
      context.read<FriendsState>().search(trimmed);
    } else {
      context.read<FriendsState>().clearSearch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = context.watch<FriendsState>();
    // Answers are on screen now, so clear the red dot.
    if (friends.hasUnseenUpdates) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<FriendsState>().markUpdatesSeen();
      });
    }

    return RefreshIndicator(
      onRefresh: () => friends.refresh(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, shelfBottomSpace(context)),
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: _runSearch,
            decoration: InputDecoration(
              hintText: context.tr('community.find_families'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchMode
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        _runSearch('');
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          if (_searchMode)
            ..._buildSearch(friends)
          else
            ..._buildFriendsAndRequests(friends),
        ],
      ),
    );
  }

  List<Widget> _buildSearch(FriendsState friends) {
    if (friends.searching) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (friends.searchResults.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Center(
            child: Text(context.tr('community.no_families'),
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
        ),
      ];
    }
    return friends.searchResults.map((m) => MemberRow(member: m)).toList();
  }

  List<Widget> _buildFriendsAndRequests(FriendsState friends) {
    // Everyone else in the community, so a friend can be added right here.
    final others = friends.notFriends;
    return [
      if (friends.updates.isNotEmpty) ...[
        CommunitySectionTitle(
            icon: Icons.campaign_rounded,
            color: const Color(0xFFFFD6A5),
            text: context.tr('community.updates')),
        ...friends.updates.map((u) => _UpdateRow(update: u)),
        const SizedBox(height: 16),
      ],
      if (friends.pending.isNotEmpty) ...[
        CommunitySectionTitle(
            icon: Icons.mark_email_unread_rounded,
            color: const Color(0xFFFFB4B4),
            text: context.tr('community.requests')),
        ...friends.pending.map((m) => _RequestRow(member: m)),
        const SizedBox(height: 16),
      ],
      CommunitySectionTitle(
          icon: Icons.favorite_rounded,
          color: const Color(0xFF9EDDB0),
          text: context.tr('community.friends')),
      if (friends.loading && friends.friends.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (friends.friends.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(context.tr('community.no_friends'),
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
        )
      else
        ...friends.friends.map((m) => MemberRow(member: m)),
      if (others.isNotEmpty) ...[
        const SizedBox(height: 18),
        CommunitySectionTitle(
            icon: Icons.person_add_alt_1_rounded,
            color: const Color(0xFF8EC9F5),
            text: context.tr('community.add_friends')),
        ...others.map((m) => MemberRow(member: m)),
      ],
    ];
  }
}

// A person in friends or search results, with a relationship-aware action.
class MemberRow extends StatelessWidget {
  final Member member;
  const MemberRow({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BoldCard(
        padding: const EdgeInsets.all(10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MemberProfilePage(caregiverId: member.caregiverId),
        )),
        child: Row(
          children: [
            MemberAvatar(
                emoji: member.avatarEmoji, colorHex: member.avatarColor, size: 54),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 17, color: communityInk)),
                  if (member.bio != null && member.bio!.isNotEmpty)
                    Text(member.bio!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            _RelationAction(member: member),
          ],
        ),
      ),
    );
  }
}

class _RelationAction extends StatelessWidget {
  final Member member;
  const _RelationAction({required this.member});

  @override
  Widget build(BuildContext context) {
    final friends = context.read<FriendsState>();
    switch (member.relation) {
      case 'friends':
        return const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.favorite_rounded, size: 30, color: AppColors.success),
        );
      case 'request_sent':
        // Waiting for them to answer.
        return Tooltip(
          message: context.tr('community.requested'),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.hourglass_top_rounded, size: 30, color: AppColors.textMuted),
          ),
        );
      case 'request_received':
        return const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.mark_email_unread_rounded, size: 30, color: AppColors.warning),
        );
      default:
        return IconButton.filled(
          tooltip: context.tr('community.add_friend'),
          iconSize: 28,
          style: IconButton.styleFrom(
            backgroundColor: communitySun,
            foregroundColor: communityInk,
            minimumSize: const Size(52, 52),
            side: const BorderSide(color: communityInk, width: 2.5),
          ),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          onPressed: () async {
            final ok = await friends.sendRequest(member.caregiverId);
            if (context.mounted && ok) {
              AppSnackbar.success(context.trRead('community.request_sent'),
                  context: context);
            }
          },
        );
    }
  }
}

// Someone accepted or declined a friend request I sent.
class _UpdateRow extends StatelessWidget {
  final FriendUpdate update;
  const _UpdateRow({required this.update});

  @override
  Widget build(BuildContext context) {
    final person = update.person;
    final text = context
        .tr(update.accepted ? 'community.accepted_you' : 'community.declined_you')
        .replaceAll('{name}', person.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BoldCard(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            MemberAvatar(
                emoji: person.avatarEmoji, colorHex: person.avatarColor, size: 54),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Icon(
              update.accepted ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: update.accepted ? AppColors.success : AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

// An incoming request with accept / decline.
class _RequestRow extends StatelessWidget {
  final Member member;
  const _RequestRow({required this.member});

  @override
  Widget build(BuildContext context) {
    final friends = context.read<FriendsState>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BoldCard(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            MemberAvatar(
                emoji: member.avatarEmoji, colorHex: member.avatarColor, size: 54),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${member.name} ${context.tr('community.wants_connect')}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            IconButton(
              icon: const Icon(Icons.check_circle_rounded,
                  color: AppColors.success),
              onPressed: () => friends.respond(member.friendshipId ?? '', true),
            ),
            IconButton(
              icon: const Icon(Icons.cancel_rounded, color: AppColors.danger),
              onPressed: () => friends.respond(member.friendshipId ?? '', false),
            ),
          ],
        ),
      ),
    );
  }
}
