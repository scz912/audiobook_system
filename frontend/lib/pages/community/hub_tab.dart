import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/community/hub_post.dart';
import '../../state/hub_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/soft_card.dart';
import '../child/audio_player_page.dart';
import 'community_widgets.dart';
import 'hub_post_detail_page.dart';
import 'member_profile_page.dart';
import 'share_to_hub_page.dart';

// Open the shared story in the player (preview mode — no session recorded).
void _listenToPost(BuildContext context, HubPost post) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => AudioPlayerPage(
      title: post.bookTitle ?? 'Story',
      audiobookId: post.audiobookId,
      previewMode: true,
    ),
  ));
}

// The shared-audiobook feed with a button to share your own book.
class HubTab extends StatefulWidget {
  const HubTab({super.key});

  @override
  State<HubTab> createState() => _HubTabState();
}

class _HubTabState extends State<HubTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hub = context.read<HubState>();
      if (hub.feed.isEmpty) hub.refresh();
    });
  }

  Future<void> _openShare() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ShareToHubPage()),
    );
    if (mounted) context.read<HubState>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubState>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openShare,
        backgroundColor: AppColors.primaryBlueDark,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(context.tr('community.share'),
            style: const TextStyle(color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: () => hub.refresh(),
        child: hub.loading && hub.feed.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : hub.feed.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      _EmptyHub(),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: hub.feed.length,
                    itemBuilder: (_, i) => _PostCard(post: hub.feed[i]),
                  ),
      ),
    );
  }
}

class _EmptyHub extends StatelessWidget {
  const _EmptyHub();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.auto_stories_rounded, size: 64, color: AppColors.textMuted),
        const SizedBox(height: 12),
        Text(context.tr('community.no_posts_title'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 6),
        Text(context.tr('community.no_posts_body'),
            style: const TextStyle(color: AppColors.textSecondary)),
      ],
    );
  }
}

class _PostCard extends StatelessWidget {
  final HubPost post;
  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final hub = context.read<HubState>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author row.
            Row(
              children: [
                GestureDetector(
                  onTap: post.author == null
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                MemberProfilePage(caregiverId: post.author!.caregiverId),
                          )),
                  child: MemberAvatar(
                    emoji: post.author?.avatarEmoji ?? '🙂',
                    colorHex: post.author?.avatarColor,
                    size: 40,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(post.author?.name ?? 'Family',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(shortAgo(post.createdAt),
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                if (post.isMine)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.textSecondary),
                    onPressed: () => _confirmDelete(context, hub, post),
                  ),
              ],
            ),
            if (post.caption != null && post.caption!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(post.caption!, style: const TextStyle(height: 1.4)),
            ],
            // The shared book (only when the post includes one).
            if (post.hasBook) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () => _listenToPost(context, post),
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  children: [
                    _Cover(url: post.coverImage),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(post.bookTitle ?? 'Story',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          if (post.bookAuthor != null && post.bookAuthor!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(post.bookAuthor!,
                                  style: const TextStyle(
                                      color: AppColors.textSecondary, fontSize: 12)),
                            ),
                        ],
                      ),
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
                  onPressed: () => _listenToPost(context, post),
                  icon: const Icon(Icons.headphones_rounded),
                  label: Text(context.tr('community.listen'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
            const Divider(height: 22),
            // Like + comment actions.
            Row(
              children: [
                _ActionButton(
                  icon: post.likedByMe
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: post.likedByMe ? AppColors.danger : AppColors.textSecondary,
                  label: '${post.likeCount}',
                  onTap: () => hub.toggleLike(post),
                ),
                const SizedBox(width: 18),
                _ActionButton(
                  icon: Icons.mode_comment_outlined,
                  color: AppColors.textSecondary,
                  label: '${post.commentCount}',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => HubPostDetailPage(post: post),
                  )),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, HubState hub, HubPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(ctx.tr('community.delete_post_title')),
        content: Text(
          ctx.tr('community.delete_post_body'),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('community.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await hub.removePost(post.postId);
    if (context.mounted && !ok) {
      AppSnackbar.error('Could not delete post', context: context);
    }
  }
}

class _Cover extends StatelessWidget {
  final String? url;
  const _Cover({this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 56,
        height: 56,
        child: (url != null && url!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                memCacheWidth: 160,
                placeholder: (_, _) => Container(color: AppColors.iconCircleBlue),
                errorWidget: (_, _, _) => const _CoverFallback(),
              )
            : const _CoverFallback(),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.softLavender,
      child: const Icon(Icons.auto_stories_rounded, color: AppColors.primaryBlueDark),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
