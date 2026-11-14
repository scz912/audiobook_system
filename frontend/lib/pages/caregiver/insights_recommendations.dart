import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/book_recommendation.dart';
import '../../models/content_item.dart';
import '../../services/audiobook_recommender.dart';
import '../../services/database_service.dart';
import '../../services/todays_mood.dart';
import '../../state/profiles_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/difficulty_badge.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/soft_card.dart';
import '../child/audio_player_page.dart';

/* "Recommended for you" on the Insights page, for every account: three
   books picked for [childId] by the server's hybrid recommender (books
   like the ones they liked, what similar readers liked, today's mood,
   the right difficulty, popular books for a new reader, and their music
   taste when YouTube access is allowed). Each says why in a few words. */
class RecommendedBooksSection extends StatefulWidget {
  final String childId;
  // Caregivers preview a book (no session recorded); a personal account listens.
  final bool previewOnOpen;

  const RecommendedBooksSection({
    super.key,
    required this.childId,
    this.previewOnOpen = true,
  });

  @override
  State<RecommendedBooksSection> createState() => _RecommendedBooksSectionState();
}

class _RecommendedBooksSectionState extends State<RecommendedBooksSection> {
  List<(BookRecommendation, ContentItem)> _picks = const [];
  String? _mood;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RecommendedBooksSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final childId = widget.childId;
    final mood = await todaysMood(context.read<ProfilesState>(), childId);
    final taste = await AudiobookRecommender.tasteForServer();
    final results = await Future.wait([
      DatabaseService.getRecommendations(childId, mood: mood, taste: taste),
      DatabaseService.getContentList(),
    ]);
    if (!mounted || childId != widget.childId) return;
    final recs = results[0].data is List<BookRecommendation>
        ? results[0].data as List<BookRecommendation>
        : const <BookRecommendation>[];
    final books = {
      if (results[1].data is List<ContentItem>)
        for (final b in results[1].data as List<ContentItem>) b.audiobookId: b,
    };
    setState(() {
      _mood = mood;
      _picks = [
        for (final r in recs)
          if (books[r.audiobookId] != null) (r, books[r.audiobookId]!),
      ];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('recs.title'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        SoftCard(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : _picks.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          const Icon(Icons.auto_stories_rounded, size: 36, color: AppColors.textMuted),
                          const SizedBox(height: 8),
                          Text(context.tr('recs.empty'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.textSecondary)),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < _picks.length; i++) ...[
                          if (i > 0) const Divider(height: 24),
                          _PickTile(
                            rec: _picks[i].$1,
                            book: _picks[i].$2,
                            mood: _mood,
                            preview: widget.previewOnOpen,
                          ),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }
}

// Why a book was picked, in a few words.
String recommendationReason(BuildContext context, BookRecommendation rec, String? mood) {
  final p = rec.reasonParams;
  switch (rec.reasonCode) {
    case 'like_book':
      return context.tr('recs.like_book').replaceAll('{title}', p['title'] ?? '');
    case 'others_liked':
      return context.tr('recs.others_liked').replaceAll('{title}', p['title'] ?? '');
    case 'fits_mood':
      final m = p['mood'] ?? mood;
      return m == null
          ? context.tr('recs.just_right')
          : context.tr('recs.fits_mood').replaceAll('{mood}', context.tr('child.mood_$m').toLowerCase());
    case 'music_taste':
      return context.tr('recs.music_taste').replaceAll('{genre}', p['genre'] ?? '');
    case 'just_right':
      return context.tr('recs.just_right');
    default:
      return context.tr('recs.popular');
  }
}

class _PickTile extends StatelessWidget {
  final BookRecommendation rec;
  final ContentItem book;
  final String? mood;
  final bool preview;

  const _PickTile({
    required this.rec,
    required this.book,
    required this.mood,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final cover = book.coverImage;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AudioPlayerPage(
          title: book.title,
          audiobookId: book.audiobookId,
          previewMode: preview,
        ),
      )),
      child: Row(
        children: [
          // Cover with the difficulty tag in front of its top-right corner.
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: (cover != null && cover.isNotEmpty)
                      ? Image.network(cover, fit: BoxFit.cover, cacheWidth: 200,
                          errorBuilder: (_, _, _) => _fallback())
                      : _fallback(),
                ),
              ),
              Positioned(top: -8, right: -14, child: DifficultyBadge(difficulty: book.difficulty)),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarqueeText(book.title, maxLines: 2,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.primaryBlueDark),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        recommendationReason(context, rec, mood),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
                if (rec.isNew) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.iconCircleGreen,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(context.tr('recs.new'),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.play_circle_outline_rounded, color: AppColors.primaryBlueDark),
        ],
      ),
    );
  }

  Widget _fallback() => Container(
        color: AppColors.softLavender,
        alignment: Alignment.center,
        child: const Icon(Icons.auto_stories_rounded, color: AppColors.primaryBlueDark),
      );
}
