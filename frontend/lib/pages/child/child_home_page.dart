import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/i18n.dart';
import '../../models/content_item.dart';
import '../../services/database_service.dart';
import '../../services/reading_progress.dart';
import '../../state/profiles_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/paige_mascot.dart';
import '../../widgets/soft_card.dart';
import '../../widgets/shelf_nav_bar.dart';
import 'audio_player_page.dart';

class ChildHomePage extends StatefulWidget {
  const ChildHomePage({
    super.key,
    this.moodCardKey,
    this.paigeKey,
    this.onPaigeTap,
  });

  // So a guide can ring the mood card and Paige.
  final GlobalKey? moodCardKey;
  final GlobalKey? paigeKey;
  // Paige in the corner replays the guide ("I'm always here").
  final VoidCallback? onPaigeTap;

  @override
  State<ChildHomePage> createState() => _ChildHomePageState();
}

class _ChildHomePageState extends State<ChildHomePage> {
  String? _selectedMood;
  // After a mood is picked it's locked until the next day. Saved per
  // (child_id, date) so the lock survives restarts and clears at midnight.
  bool _moodLockedForToday = false;
  ContentItem? _featured;
  // The book this child left part-way through, if any.
  ReadingProgress? _progress;

  // Mood `labelKey` is a translation key, resolved with context.tr().
  static const List<_Mood> _moods = [
    _Mood('happy', 'child.mood_happy', '😊', AppColors.moodHappy),
    _Mood('calm', 'child.mood_calm', '😌', AppColors.moodCalm),
    _Mood('curious', 'child.mood_curious', '🤔', AppColors.moodCurious),
    _Mood('sleepy', 'child.mood_sleepy', '😴', AppColors.moodSleepy),
  ];

  @override
  void initState() {
    super.initState();
    _loadFeatured();
    _loadTodayMood();
    _loadProgress();
    ReadingProgress.changed.addListener(_loadProgress);
  }

  @override
  void dispose() {
    ReadingProgress.changed.removeListener(_loadProgress);
    super.dispose();
  }

  Future<void> _loadProgress() async {
    final childId = context.read<ProfilesState>().activeProfile?.childId;
    if (childId == null) return;
    final p = await ReadingProgress.load(childId);
    if (mounted) setState(() => _progress = p);
  }

  void _continueReading(ReadingProgress p) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AudioPlayerPage(
        title: p.title,
        audiobookId: p.audiobookId,
        resumeFrom: p,
      ),
    ));
  }

  Future<void> _loadFeatured() async {
    final resp = await DatabaseService.getContentList();
    if (!mounted) return;
    if (resp.success && resp.data is List<ContentItem>) {
      final items = resp.data as List<ContentItem>;
      // Only feature a finished book (skip ones still making pictures).
      final ready = items.where((i) => i.status != 'processing').toList();
      setState(() => _featured = ready.isNotEmpty ? ready.first : null);
    }
  }

  /* The storage key for [childId]'s mood today. Uses the local date, so a
     tap at 11 PM unlocks at midnight, not 24 hours later. */
  String _todayMoodKey(String childId) {
    final now = DateTime.now();
    final ymd = '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return 'mood_${childId}_$ymd';
  }

  /* Load today's saved mood when the page opens, so the lock holds after
     leaving and re-entering Child Mode the same day. */
  Future<void> _loadTodayMood() async {
    final profile = context.read<ProfilesState>().activeProfile;
    if (profile == null) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_todayMoodKey(profile.childId));
    if (saved == null || !mounted) return;
    setState(() {
      _selectedMood = saved;
      _moodLockedForToday = true;
    });
    // Re-apply the mood so the next session uses it (it resets on entry).
    if (!mounted) return;
    context.read<ProfilesState>().setMood(saved);
  }

  /* Save today's mood for [childId]. The UI lock keeps this to once a day. */
  Future<void> _saveMoodForToday(String childId, String moodId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_todayMoodKey(childId), moodId);
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfilesState>().activeProfile;
    final name = profile?.name ?? context.tr('child.default_name');
    final emoji = profile?.avatarEmoji ?? '🌸';
    final avatarColor = profile?.avatarColor ?? AppColors.softPink;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 12, 20, shelfBottomSpace(context)),
      children: [
        const SizedBox(height: 8),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Container(
                width: 88, height: 88,
                decoration: BoxDecoration(color: avatarColor, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 44)),
              ),
            ),
            if (widget.onPaigeTap != null)
              Positioned(
                right: 0,
                top: -4,
                child: Semantics(
                  button: true,
                  label: context.tr('guide.replay'),
                  child: GestureDetector(
                    key: widget.paigeKey,
                    onTap: widget.onPaigeTap,
                    child: const PaigeMascot(width: 72),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🌅 ', style: TextStyle(fontSize: 24)),
            Text(
              '$name!',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (_progress != null) ...[
          _ContinueCard(
            progress: _progress!,
            onTap: () => _continueReading(_progress!),
          ),
          const SizedBox(height: 18),
        ],

        SoftCard(
          key: widget.moodCardKey,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  context.tr('child.mood_question'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                // Without an explicit padding the grid inherits the screen's
                // bottom inset (nav bar / safe area) as blank space.
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: _moods.map((m) {
                  final selected = _selectedMood == m.id;
                  // Once locked, the unpicked cards fade so only the chosen
                  // one stands out.
                  final dimmed = _moodLockedForToday && !selected;
                  return InkWell(
                    onTap: () {
                      if (_moodLockedForToday) {
                        // Already chose today - explain why other cards don't
                        // respond.
                        final chosen = _selectedMood;
                        if (chosen != null) {
                          final chosenLabel = _moods
                              .firstWhere((x) => x.id == chosen)
                              .labelKey;
                          AppSnackbar.info(
                            context
                                .trRead('child.mood_locked')
                                .replaceAll('{mood}',
                                    context.trRead(chosenLabel)),
                            context: context,
                          );
                        }
                        return;
                      }
                      final childId = context
                          .read<ProfilesState>()
                          .activeProfile
                          ?.childId;
                      setState(() {
                        _selectedMood = m.id;
                        _moodLockedForToday = true;
                      });
                      context.read<ProfilesState>().setMood(m.id);
                      if (childId != null) _saveMoodForToday(childId, m.id);
                      AppSnackbar.success(
                        context.trRead('child.mood_saved').replaceAll(
                            '{mood}', context.trRead(m.labelKey)),
                        context: context,
                      );
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: dimmed ? 0.4 : 1.0,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 180),
                        scale: selected ? 1.04 : 1.0,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: m.color,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected
                                  ? AppColors.textPrimary
                                  : Colors.transparent,
                              // Thicker border when picked, easy to see at
                              // arm's length.
                              width: selected ? 4 : 0,
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.12),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Stack(
                            children: [
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(m.emoji,
                                        style:
                                            const TextStyle(fontSize: 36)),
                                    const SizedBox(height: 4),
                                    Text(context.tr(m.labelKey),
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                              if (selected)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: const BoxDecoration(
                                      color: AppColors.success,
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.check_rounded,
                                        color: Colors.white, size: 16),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        if (_featured != null) ...[
          const SizedBox(height: 18),
          _StartStoryCard(
            story: _featured!,
            onStart: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AudioPlayerPage(
                title: _featured!.title,
                audiobookId: _featured!.audiobookId,
              ),
            )),
          ),
        ],
      ],
    );
  }
}

class _Mood {
  final String id;
  // Translation key for the label.
  final String labelKey;
  final String emoji;
  final Color color;
  const _Mood(this.id, this.labelKey, this.emoji, this.color);
}

/* "Continue reading": the book left part-way through, how far along it
   is, and a big play button that opens it at that page. */
class _ContinueCard extends StatelessWidget {
  final ReadingProgress progress;
  final VoidCallback onTap;
  const _ContinueCard({required this.progress, required this.onTap});

  static const _ink = Color(0xFF26215C);

  @override
  Widget build(BuildContext context) {
    final total = progress.totalPages;
    final shown = progress.pageNumber.clamp(1, total < 1 ? 1 : total);
    final fraction = total > 0 ? shown / total : 0.0;
    return Semantics(
      button: true,
      label: '${context.tr('child.continue_reading')}: ${progress.title}',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFE9A8), Color(0xFFFFC9A8)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _ink, width: 3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bookmark_rounded, size: 20, color: _ink),
                    const SizedBox(width: 6),
                    Text(
                      context.tr('child.continue_reading').toUpperCase(),
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StartStoryCover(url: progress.coverImage),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            progress.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              height: 1.2,
                            ),
                          ),
                          if (total > 1) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: fraction,
                                minHeight: 10,
                                color: _ink,
                                backgroundColor: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context
                                  .tr('player.page_of')
                                  .replaceAll('{current}', '$shown')
                                  .replaceAll('{total}', '$total'),
                              style: const TextStyle(
                                color: _ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: _ink, width: 3),
                      ),
                      child: const Icon(Icons.play_arrow_rounded, size: 40, color: _ink),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* The big "Today's pick" button on the child home. Solid gradient and a
   solid white button - no see-through pills or glows, which made the text
   look blurry before. */
class _StartStoryCard extends StatelessWidget {
  final ContentItem story;
  final VoidCallback onStart;
  const _StartStoryCard({required this.story, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onStart,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryBlue, AppColors.primaryBlueDark],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // "TODAY'S PICK" label - plain white text.
              Row(
                children: [
                  const Icon(Icons.star_rounded,
                      size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    context.tr('child.featured').toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Cover and title.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _StartStoryCover(url: story.coverImage),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      story.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Full-width white start button: a big play icon, no words.
              Semantics(
                button: true,
                label: context.tr('child.start_story'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      size: 40, color: AppColors.primaryBlueDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* Square cover next to the title. Shows a book icon when there's no cover
   yet (still generating). */
class _StartStoryCover extends StatelessWidget {
  final String? url;
  const _StartStoryCover({this.url});

  @override
  Widget build(BuildContext context) {
    final src = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 70,
        height: 70,
        child: (src != null && src.isNotEmpty)
            ? Image.network(
                src,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Container(
        color: AppColors.softLavender,
        alignment: Alignment.center,
        child: const Icon(Icons.menu_book_rounded,
            color: AppColors.textPrimary, size: 30),
      );
}
