import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/i18n.dart';
import '../../models/content_item.dart';
import '../../services/audiobook_recommender.dart';
import '../../services/database_service.dart';
import '../../services/music_genres.dart';
import '../../services/music_taste_service.dart';
import '../../state/profiles_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/difficulty_badge.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/soft_card.dart';
import '../child/audio_player_page.dart';

/* Personal account only, on the Insights page after "Top stories":

   1. Top Music Genre - the three listening genres played most on YouTube
      and YouTube Music in the last 30 days (MusicTasteService).
   2. Recommended for you - three audiobooks whose background music suits
      those genres and today's mood (AudiobookRecommender, no AI).

   Both stay empty with an "Allow YouTube Access" button until the person
   turns on access; coming back from Android's settings refreshes them. */
class MusicTasteSections extends StatefulWidget {
  const MusicTasteSections({super.key});

  @override
  State<MusicTasteSections> createState() => _MusicTasteSectionsState();
}

class _MusicTasteSectionsState extends State<MusicTasteSections> with WidgetsBindingObserver {
  MusicTasteStatus? _status;
  // The card's rows: the top genres, then Others (songs of unknown genre).
  List<GenreShare> _top = const [];
  // The top genres alone, which the recommendations go by.
  List<GenreShare> _tasteTop = const [];
  Map<String, int> _counts = const {};
  List<Recommendation> _recs = const [];
  String? _mood;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from Android's settings (or from YouTube): look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final status = await MusicTasteService.status();
    if (!mounted) return;
    if (!status.granted) {
      setState(() {
        _status = status;
        _loading = false;
      });
      return;
    }
    await MusicTasteService.sync();
    final counts = await MusicTasteService.genreCounts();
    final top = AudiobookRecommender.topGenres(counts, withOthers: true);
    final tasteTop = AudiobookRecommender.topGenres(counts);
    final mood = await _todaysMood();
    var books = <ContentItem>[];
    if (tasteTop.isNotEmpty) {
      final resp = await DatabaseService.getContentList();
      if (resp.success && resp.data is List<ContentItem>) books = resp.data as List<ContentItem>;
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _counts = counts;
      _top = top;
      _tasteTop = tasteTop;
      _mood = mood;
      _recs = AudiobookRecommender.recommend(books, tasteTop, mood);
      _loading = false;
    });
  }

  // The mood picked on the home page today, if any.
  Future<String?> _todaysMood() async {
    final profiles = context.read<ProfilesState>();
    if (profiles.currentMood != null) return profiles.currentMood;
    final childId = profiles.activeProfile?.childId;
    if (childId == null) return null;
    final now = DateTime.now();
    final ymd = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return (await SharedPreferences.getInstance()).getString('mood_${childId}_$ymd');
  }

  /* Set once the person has been sent to Android's access page. If they
     come back still without access on an Android 13+ APK install, the
     switch was most likely locked ("Restricted setting"), so the card
     then shows how to unlock it. Not before: Android only offers "Allow
     restricted settings" in App info after the locked switch was tapped. */
  bool _triedSettings = false;

  Future<void> _askForAccess() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(ctx.tr('music.allow_title')),
        content: SingleChildScrollView(child: Text(ctx.tr('music.allow_explain'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('music.not_now'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlueDark),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('music.open_settings')),
          ),
        ],
      ),
    );
    if (go == true) {
      _triedSettings = true;
      await MusicTasteService.openSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        _Header(title: context.tr('music.top_genre'), subtitle: context.tr('music.top_genre_sub')),
        const SizedBox(height: 10),
        SoftCard(child: _genres(context)),
        const SizedBox(height: 20),
        _Header(title: context.tr('music.recs'), subtitle: context.tr('music.recs_sub')),
        const SizedBox(height: 10),
        SoftCard(child: _recommendations(context)),
      ],
    );
  }

  // Nothing to show yet: loading, not possible here, or not allowed.
  Widget? _gate(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final status = _status!;
    if (!status.supported) return _Notice(icon: Icons.phone_android_rounded, text: context.tr('music.not_supported'));
    if (!status.granted) {
      return _AllowPrompt(onAllow: _askForAccess, showUnlock: _triedSettings && status.mayBeRestricted);
    }
    return null;
  }

  Widget _genres(BuildContext context) {
    final gate = _gate(context);
    if (gate != null) return gate;
    // Access is on but the phone stopped the listener: say so, or the
    // card would just wait for plays that never get seen.
    final paused = !_status!.listening
        ? _Notice(
            icon: Icons.battery_alert_rounded,
            text: context.tr('music.paused'),
            action: TextButton(
              onPressed: MusicTasteService.openAppInfo,
              child: Text(context.tr('music.open_app_info')),
            ),
          )
        : null;
    if (_top.isEmpty) return paused ?? _Notice(icon: Icons.music_note_rounded, text: context.tr('music.no_plays'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (paused != null) ...[paused, const Divider(height: 24)],
        for (var i = 0; i < _top.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _GenreRow(
            // Others isn't ranked: it's not a taste.
            rank: _top[i].genre == otherGenre ? 0 : i + 1,
            label: context.tr('music.genre.${_top[i].genre}'),
            plays: _counts[_top[i].genre] ?? 0,
            share: _top[i].share,
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: MusicTasteService.openSettings,
            child: Text(context.tr('music.manage')),
          ),
        ),
      ],
    );
  }

  Widget _recommendations(BuildContext context) {
    final gate = _gate(context);
    if (gate != null) return gate;
    if (_tasteTop.isEmpty) return _Notice(icon: Icons.auto_stories_rounded, text: context.tr('music.recs_need_plays'));
    if (_recs.isEmpty) return _Notice(icon: Icons.auto_stories_rounded, text: context.tr('music.recs_none'));
    return Column(
      children: [
        for (var i = 0; i < _recs.length; i++) ...[
          if (i > 0) const Divider(height: 24),
          _RecommendationTile(rec: _recs[i], mood: _mood),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  const _Header({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      );
}

// The empty box with the way in.
class _AllowPrompt extends StatelessWidget {
  final VoidCallback onAllow;
  // Show how to unlock a "Restricted setting" switch (see _triedSettings).
  final bool showUnlock;
  const _AllowPrompt({required this.onAllow, this.showUnlock = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            const Icon(Icons.smart_display_rounded, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 10),
            Text(
              context.tr('music.allow_body'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlueDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: onAllow,
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: Text(context.tr('music.allow')),
            ),
            if (showUnlock) ...[
              const SizedBox(height: 16),
              Text(
                context.tr('music.restricted_hint'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: MusicTasteService.openAppInfo,
                child: Text(context.tr('music.open_app_info')),
              ),
            ],
          ],
        ),
      );
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const _Notice({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Icon(icon, size: 36, color: AppColors.textMuted),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            if (action != null) ...[const SizedBox(height: 6), action!],
          ],
        ),
      );
}

class _GenreRow extends StatelessWidget {
  final int rank;
  final String label;
  final int plays;
  final double share;
  const _GenreRow({required this.rank, required this.label, required this.plays, required this.share});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: rank == 1 ? AppColors.primaryBlueDark : AppColors.iconCircleBlue,
            shape: BoxShape.circle,
          ),
          child: Text(
            rank == 0 ? '?' : '$rank',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: rank == 1 ? Colors.white : AppColors.primaryBlueDark,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  Text(
                    context.tr('music.plays').replaceAll('{n}', '$plays'),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: share,
                  minHeight: 8,
                  color: AppColors.primaryBlueDark,
                  backgroundColor: AppColors.background,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecommendationTile extends StatelessWidget {
  final Recommendation rec;
  final String? mood;
  const _RecommendationTile({required this.rec, required this.mood});

  @override
  Widget build(BuildContext context) {
    final book = rec.book;
    final cover = book.coverImage;
    final reasons = [
      if (rec.becauseGenre != null)
        context.tr('music.because').replaceAll('{genre}', context.tr('music.genre.${rec.becauseGenre}')),
      if (rec.moodTags.isNotEmpty && mood != null)
        context.tr('music.fits_mood').replaceAll('{mood}', context.tr('child.mood_$mood').toLowerCase()),
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AudioPlayerPage(title: book.title, audiobookId: book.audiobookId),
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
                if (reasons.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(reasons.join(' · '),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                ],
                if (book.musicTrack?.genre != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    context.tr('music.bgm').replaceAll('{genre}', book.musicTrack!.genre!),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
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
