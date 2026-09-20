import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/community/hub_comment.dart';
import '../../models/community/hub_post.dart';
import '../../services/database_service.dart';
import '../../state/hub_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/soft_card.dart';
import '../child/audio_player_page.dart';
import 'community_widgets.dart';
import 'member_profile_page.dart';

// A shared post with its comments and a comment box.
class HubPostDetailPage extends StatefulWidget {
  final HubPost post;
  const HubPostDetailPage({super.key, required this.post});

  @override
  State<HubPostDetailPage> createState() => _HubPostDetailPageState();
}

class _HubPostDetailPageState extends State<HubPostDetailPage> {
  final _commentCtrl = TextEditingController();
  List<HubComment> _comments = const [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    final resp = await DatabaseService.postComments(widget.post.postId);
    if (!mounted) return;
    setState(() {
      _comments = resp.success && resp.data is List<HubComment>
          ? resp.data as List<HubComment>
          : const [];
      _loading = false;
    });
  }

  Future<void> _send() async {
    final body = _commentCtrl.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    final resp = await DatabaseService.addPostComment(widget.post.postId, body);
    if (!mounted) return;
    setState(() => _sending = false);
    if (resp.success && resp.data is HubComment) {
      setState(() {
        _comments = [..._comments, resp.data as HubComment];
        _commentCtrl.clear();
      });
    } else {
      AppSnackbar.error(resp.message, context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
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
                  Text(context.tr('community.post'),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  _PostHeader(post: post),
                  const SizedBox(height: 16),
                  Text(context.tr('community.comments'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(context.tr('community.no_comments'),
                            style: const TextStyle(color: AppColors.textSecondary)),
                      ),
                    )
                  else
                    ..._comments.map((c) => _CommentTile(comment: c)),
                ],
              ),
            ),
            _CommentBox(
              controller: _commentCtrl,
              sending: _sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _PostHeader extends StatelessWidget {
  final HubPost post;
  const _PostHeader({required this.post});

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubState>();
    // Prefer the live copy from the feed so likes stay in sync.
    final live = hub.feed.firstWhere(
      (p) => p.postId == post.postId,
      orElse: () => post,
    );
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: live.author == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => MemberProfilePage(
                              caregiverId: live.author!.caregiverId),
                        )),
                child: MemberAvatar(
                  emoji: live.author?.avatarEmoji ?? '🙂',
                  colorHex: live.author?.avatarColor,
                  size: 40,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(live.author?.name ?? 'Family',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(shortAgo(live.createdAt),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
          if (live.caption != null && live.caption!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(live.caption!, style: const TextStyle(height: 1.4)),
          ],
          if (live.hasBook) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AudioPlayerPage(
                  title: live.bookTitle ?? 'Story',
                  audiobookId: live.audiobookId,
                  previewMode: true,
                ),
              )),
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: (live.coverImage != null && live.coverImage!.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: live.coverImage!,
                              fit: BoxFit.cover,
                              memCacheWidth: 180,
                              errorWidget: (_, _, _) => Container(
                                color: AppColors.softLavender,
                                child: const Icon(Icons.auto_stories_rounded,
                                    color: AppColors.primaryBlueDark),
                              ),
                            )
                          : Container(
                              color: AppColors.softLavender,
                              child: const Icon(Icons.auto_stories_rounded,
                                  color: AppColors.primaryBlueDark),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(live.bookTitle ?? 'Story',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  const Icon(Icons.play_circle_fill_rounded,
                      color: AppColors.primaryBlueDark, size: 34),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AudioPlayerPage(
                    title: live.bookTitle ?? 'Story',
                    audiobookId: live.audiobookId,
                    previewMode: true,
                  ),
                )),
                icon: const Icon(Icons.headphones_rounded),
                label: Text(context.tr('community.listen'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
          const Divider(height: 22),
          InkWell(
            onTap: () => hub.toggleLike(live),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    live.likedByMe
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: live.likedByMe
                        ? AppColors.danger
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text('${live.likeCount} ${context.tr('community.likes')}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final HubComment comment;
  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MemberAvatar(
            emoji: comment.author?.avatarEmoji ?? '🙂',
            colorHex: comment.author?.avatarColor,
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.author?.name ?? 'Family',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(width: 8),
                    Text(shortAgo(comment.createdAt),
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.body, style: const TextStyle(height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentBox extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _CommentBox({
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
                decoration: InputDecoration(
                    hintText: context.tr('community.write_comment')),
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
