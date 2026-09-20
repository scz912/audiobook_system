import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/community/conversation.dart';
import '../../state/chat_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/soft_card.dart';
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NewGroupPage()),
          );
          if (context.mounted) context.read<ChatState>().refresh();
        },
        backgroundColor: AppColors.primaryBlueDark,
        icon: const Icon(Icons.group_add_rounded, color: Colors.white),
        label: Text(context.tr('community.new_group'),
            style: const TextStyle(color: Colors.white)),
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
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
      child: SoftCard(
        padding: const EdgeInsets.all(12),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChatThreadPage(conversation: conversation),
          ));
          if (context.mounted) context.read<ChatState>().refresh();
        },
        child: Row(
          children: [
            MemberAvatar(emoji: emoji, colorHex: color, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(conversation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
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
                            fontWeight: conversation.unreadCount > 0
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (conversation.unreadCount > 0) ...[
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
