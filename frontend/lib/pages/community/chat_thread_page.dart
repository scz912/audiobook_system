import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/community/chat_message.dart';
import '../../models/community/conversation.dart';
import '../../services/database_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/back_pill.dart';
import 'community_widgets.dart';
import 'member_profile_page.dart';

/* One chat thread. Messages refresh every few seconds by polling — simple
   and works on any host. Swap for WebSockets later if you want live push. */
class ChatThreadPage extends StatefulWidget {
  final Conversation conversation;
  const ChatThreadPage({super.key, required this.conversation});

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  final _msgCtrl = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  Timer? _poll;

  String get _conversationId => widget.conversation.conversationId;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
    // Poll for new messages while the thread is open.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    final resp = await DatabaseService.conversationMessages(_conversationId);
    if (!mounted) return;
    if (resp.success && resp.data is List<ChatMessage>) {
      final incoming = resp.data as List<ChatMessage>;
      final grew = incoming.length != _messages.length;
      setState(() {
        _messages = incoming;
        _loading = false;
      });
      if (initial || grew) _scrollToBottom();
    } else {
      setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final body = _msgCtrl.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    final resp = await DatabaseService.sendChatMessage(_conversationId, body);
    if (!mounted) return;
    setState(() => _sending = false);
    if (resp.success && resp.data is ChatMessage) {
      setState(() {
        _messages = [..._messages, resp.data as ChatMessage];
        _msgCtrl.clear();
      });
      _scrollToBottom();
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
                  Expanded(
                    child: Text(widget.conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? const Center(
                          child: Text('Say hello 👋',
                              style: TextStyle(color: AppColors.textSecondary)))
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) => _Bubble(
                            message: _messages[i],
                            showSender: widget.conversation.isGroup,
                          ),
                        ),
            ),
            _Composer(
              controller: _msgCtrl,
              sending: _sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool showSender;
  const _Bubble({required this.message, required this.showSender});

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    // In group chats, show the sender's name + a tappable avatar on others'
    // messages so you can open their profile.
    final showAvatar = showSender && !mine;

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.66),
      decoration: BoxDecoration(
        color: mine ? AppColors.primaryBlue : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAvatar)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                message.senderName,
                style: const TextStyle(
                  color: AppColors.primaryBlueDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          Text(message.body,
              style: const TextStyle(color: AppColors.textPrimary, height: 1.35)),
          const SizedBox(height: 3),
          Text(
            exactTime(message.sentAt),
            style: TextStyle(
              // Darker on my blue bubble so it's readable; muted on white.
              color: mine ? AppColors.textSecondary : AppColors.textMuted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showAvatar) ...[
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MemberProfilePage(caregiverId: message.senderId),
              )),
              child: MemberAvatar(
                emoji: message.senderEmoji,
                colorHex: message.senderColor,
                size: 32,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(hintText: 'Message…'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded, color: AppColors.primaryBlueDark),
            ),
          ],
        ),
      ),
    );
  }
}
