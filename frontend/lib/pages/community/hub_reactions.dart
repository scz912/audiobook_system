import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../models/community/hub_post.dart';
import '../../theme/app_colors.dart';

/* Likes and emoji reactions under a hub post. They're separate:

   - The heart is the like button (liked or not, with the like count).
   - The smiley-plus button picks my one emoji reaction.
   - The chips show the emoji people left and how many. Tapping my own
     takes it off; tapping another moves my reaction there. Either way I'm
     counted once, and the like isn't touched. */
class ReactionBar extends StatelessWidget {
  final HubPost post;
  final void Function(String emoji) onReact;
  final VoidCallback onToggle;
  // How many emoji chips to show beside the buttons.
  final int maxChips;
  const ReactionBar({
    super.key,
    required this.post,
    required this.onReact,
    required this.onToggle,
    this.maxChips = 3,
  });

  Future<void> _pick(BuildContext context) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(sheet.tr('community.react'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in HubPost.reactionEmoji)
                    Semantics(
                      button: true,
                      selected: post.myReaction == e,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: () => Navigator.of(sheet).pop(e),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: post.myReaction == e
                                ? AppColors.primaryBlue
                                : AppColors.background,
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (emoji != null) onReact(emoji);
  }

  @override
  Widget build(BuildContext context) {
    final mine = post.myReaction;
    final chips = post.reactions.take(maxChips).toList();
    final likeColor = post.likedByMe ? AppColors.danger : AppColors.textSecondary;
    return Row(
      children: [
        Semantics(
          button: true,
          toggled: post.likedByMe,
          label: context.tr('community.like'),
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Icon(
                    post.likedByMe
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 22,
                    color: likeColor,
                  ),
                  const SizedBox(width: 6),
                  Text('${post.likeCount}',
                      style: TextStyle(
                          color: likeColor, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: context.tr('community.react'),
          visualDensity: VisualDensity.compact,
          onPressed: () => _pick(context),
          icon: const Icon(Icons.add_reaction_outlined,
              size: 21, color: AppColors.textSecondary),
        ),
        // The emoji people used, most first.
        for (final r in chips)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: InkWell(
              onTap: () => onReact(r.emoji),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: r.emoji == mine
                      ? AppColors.primaryBlue
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${r.emoji} ${r.count}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
      ],
    );
  }
}
