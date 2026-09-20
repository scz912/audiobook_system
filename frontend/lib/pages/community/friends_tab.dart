import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/community/member.dart';
import '../../state/friends_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/soft_card.dart';
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

    return RefreshIndicator(
      onRefresh: () => friends.refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
    return friends.searchResults.map((m) => _MemberRow(member: m)).toList();
  }

  List<Widget> _buildFriendsAndRequests(FriendsState friends) {
    return [
      if (friends.pending.isNotEmpty) ...[
        _SectionLabel(context.tr('community.requests')),
        ...friends.pending.map((m) => _RequestRow(member: m)),
        const SizedBox(height: 16),
      ],
      _SectionLabel(context.tr('community.friends')),
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
        ...friends.friends.map((m) => _MemberRow(member: m)),
    ];
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
    );
  }
}

// A person in friends or search results, with a relationship-aware action.
class _MemberRow extends StatelessWidget {
  final Member member;
  const _MemberRow({required this.member});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MemberProfilePage(caregiverId: member.caregiverId),
        )),
        child: Row(
          children: [
            MemberAvatar(
                emoji: member.avatarEmoji, colorHex: member.avatarColor, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
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
        return const Icon(Icons.people_rounded, color: AppColors.primaryBlueDark);
      case 'request_sent':
        return Text(context.tr('community.requested'),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12));
      case 'request_received':
        return const Icon(Icons.mark_email_unread_rounded,
            color: AppColors.warning);
      default:
        return IconButton(
          icon: const Icon(Icons.person_add_alt_1_rounded,
              color: AppColors.primaryBlueDark),
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

// An incoming request with accept / decline.
class _RequestRow extends StatelessWidget {
  final Member member;
  const _RequestRow({required this.member});

  @override
  Widget build(BuildContext context) {
    final friends = context.read<FriendsState>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            MemberAvatar(
                emoji: member.avatarEmoji, colorHex: member.avatarColor, size: 44),
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
