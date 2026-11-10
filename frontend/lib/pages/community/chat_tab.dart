import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/community/conversation.dart';
import '../../state/chat_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/shelf_nav_bar.dart';
import 'chat_thread_page.dart';
import 'community_widgets.dart';
import 'new_group_page.dart';

// The list of chat threads, newest activity first.
class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatState>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatState>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      // Lifted by the shelf height, since the page runs down behind the shelf.
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: CommunityFab(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NewGroupPage()),
            );
            if (context.mounted) context.read<ChatState>().refresh();
          },
          icon: Icons.group_add_rounded,
          label: context.tr('community.new_group'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => chat.refresh(),
        child: chat.loading && chat.conversations.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : chat.conversations.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Column(
                          children: [
                            const Icon(Icons.forum_outlined,
                                size: 64, color: AppColors.textMuted),
                            const SizedBox(height: 12),
                            Text(context.tr('community.no_chats_title'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(height: 6),
                            Text(context.tr('community.no_chats_body'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, shelfBottomSpace(context) + 72),
                    itemCount: chat.conversations.length,
                    itemBuilder: (_, i) => _ChatRow(conversation: chat.conversations[i]),
                  ),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  final Conversation conversation;
  const _ChatRow({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final emoji = conversation.isGroup
        ? '👨‍👩‍👧'
        : (conversation.participants.isNotEmpty
            ? conversation.participants.first.avatarEmoji
            : '🙂');
    final color = conversation.isGroup
        ? '#E6DCEE'
        : (conversation.participants.isNotEmpty
            ? conversation.participants.first.avatarColor
            : null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BoldCard(
        padding: const EdgeInsets.all(12),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChatThreadPage(conversation: conversation),
          ));
          if (context.mounted) context.read<ChatState>().refresh();
        },
        child: Row(
          children: [
            MemberAvatar(emoji: emoji, colorHex: color, size: 54),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Name and its icons take the space; the time stays right.
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(conversation.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17,
                                      color: communityInk)),
                            ),
                            if (conversation.isFavorite) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.star_rounded,
                                  size: 17,
                                  color: const Color(0xFFE0A100),
                                  semanticLabel: context.tr('contacts.favorite')),
                            ],
                            if (conversation.isBlocked) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.block_rounded,
                                  size: 15,
                                  color: AppColors.danger,
                                  semanticLabel: context.tr('contacts.blocked')),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(shortAgo(conversation.lastActivity),
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.lastMessageBody ??
                              context.tr('community.no_messages'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: conversation.unreadCount > 0 &&
                                    !conversation.isMuted
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      // Muted: no red badge, just the muted bell.
                      if (conversation.isMuted) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.notifications_off_rounded,
                            size: 16,
                            color: AppColors.textMuted,
                            semanticLabel: context.tr('contacts.muted')),
                      ] else if (conversation.unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        CountBadge(count: conversation.unreadCount),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
