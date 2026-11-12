import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../models/insights_overview.dart';
import '../theme/app_colors.dart';
import 'marquee_text.dart';
import 'soft_card.dart';

/* One of the most-listened books: cover with its rank, the title (two
   lines; a longer one scrolls up through them) and the listening time in
   large type. Used for the "Top 3 Books" on the caregiver dashboard and on
   the personal account's home page. */
class TopBookTile extends StatelessWidget {
  final int rank;
  final TopStory story;
  final VoidCallback onTap;
  const TopBookTile({
    super.key,
    required this.rank,
    required this.story,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cover = story.coverImage;
    return SoftCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: (cover != null && cover.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          memCacheWidth: 250,
                          errorWidget: (_, _, _) => _coverFallback(),
                        )
                      : _coverFallback(),
                ),
              ),
              Positioned(
                left: -6,
                top: -6,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlueDark,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarqueeText(
                  story.title,
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${story.minutes}',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryBlueDark,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      context.tr('caregiver.minutes_short'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.play_circle_outline_rounded,
              color: AppColors.primaryBlueDark),
        ],
      ),
    );
  }

  Widget _coverFallback() => Container(
        color: AppColors.softLavender,
        alignment: Alignment.center,
        child: const Icon(Icons.auto_stories_rounded,
            color: AppColors.primaryBlueDark, size: 32),
      );
}
