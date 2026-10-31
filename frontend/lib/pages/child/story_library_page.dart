import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../models/content_item.dart';
import '../../models/quran.dart';
import '../../services/api_service.dart';
import '../../services/database_service.dart';
import '../../services/quran_pack_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/quran_element_thumb.dart';
import '../../widgets/segmented_slider.dart';
import '../../widgets/soft_card.dart';
import '../../widgets/soft_chip.dart';
import 'audio_player_page.dart';
import 'quran_player_page.dart';

/* The same three kinds of audiobook as the caregiver's Content Management
   slider. */
enum _Library { linear, interactive, quran }

class StoryLibraryPage extends StatefulWidget {
  /* Optional back-arrow override. As a tab body, ChildShell passes a
     callback to go to the Home tab. When pushed as a normal route this is
     null and Navigator.maybePop() is used. */
  final VoidCallback? onBack;
  const StoryLibraryPage({super.key, this.onBack});

  @override
  State<StoryLibraryPage> createState() => _StoryLibraryPageState();
}

class _StoryLibraryPageState extends State<StoryLibraryPage> {
  final _searchCtrl = TextEditingController();
  _Library _library = _Library.linear;
  String _type = 'all'; // 'all' | 'audio' | 'text' | 'ai'
  String _ageRange = 'all';
  String _language = 'all'; // 'all' | 'en' | 'ms'
  bool _filtersOpen = true;

  List<ContentItem> _stories = const [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  static const _ageRanges = ['all', '5-6', '7-9', '8-11', '9-12'];

  @override
  void initState() {
    super.initState();
    _loadStories();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStories({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final ApiResponse resp = await DatabaseService.getContentList();
    if (!mounted) return;
    if (resp.success && resp.data is List<ContentItem>) {
      setState(() {
        _stories = resp.data as List<ContentItem>;
        _loading = false;
      });
    } else if (!silent) {
      setState(() {
        _stories = const [];
        _error = resp.message;
        _loading = false;
      });
      AppSnackbar.error(
          '${context.trRead('library.load_error')}: ${resp.message}',
          context: context);
    }
    _syncPolling();
  }

  /* Keep checking while a book is generating, so it shows up once its
     pictures are ready, then stop. */
  void _syncPolling() {
    final stillGenerating = _stories.any((s) => s.status == 'processing');
    if (stillGenerating) {
      _pollTimer ??= Timer.periodic(
        const Duration(seconds: 5),
        (_) => _loadStories(silent: true),
      );
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  // Finished books of the selected format. Books still generating pictures
  // stay hidden.
  List<ContentItem> get _inFormat => _stories
      .where((s) => s.status != 'processing' && s.bookFormat == _library.name)
      .toList();

  // Same rule as the caregiver's type filter (see getContentList).
  bool _matchesType(ContentItem s) {
    switch (_type) {
      case 'audio':
        return s.type == 'Audio' && !s.isGenerated;
      case 'text':
        return s.type == 'Text' && !s.isGenerated;
      case 'ai':
        return s.isGenerated;
      default:
        return true;
    }
  }

  List<ContentItem> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _inFormat.where((s) {
      if (!_matchesType(s)) return false;
      if (_ageRange != 'all') {
        final age = (s.ageGroup ?? '').toLowerCase();
        if (age != _ageRange) return false;
      }
      if (_language != 'all') {
        // Books default to 'en', so treat a null language as English here.
        final lang = (s.language ?? 'en').toLowerCase();
        if (lang != _language) return false;
      }
      if (q.isNotEmpty) {
        final hay = '${s.title} ${s.author ?? ''} ${s.topic ?? ''} '
                '${s.category ?? ''} ${s.tags ?? ''}'
            .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  bool get _filtersActive =>
      _type != 'all' ||
      _ageRange != 'all' ||
      _language != 'all' ||
      _searchCtrl.text.trim().isNotEmpty;

  void _clearFilters() {
    setState(() {
      _type = 'all';
      _ageRange = 'all';
      _language = 'all';
      _searchCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final stories = _filtered;
    final showQuran = _library == _Library.quran;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadStories,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              BackPill(onTap: widget.onBack ?? () => Navigator.of(context).maybePop()),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('library.title'),
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: AppColors.softPink,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text('🌸', style: TextStyle(fontSize: 32)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('library.subtitle'),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              SegmentedSlider<_Library>(
                value: _library,
                onChanged: (l) => setState(() => _library = l),
                items: [
                  SegmentedSliderItem(_Library.linear,
                      context.tr('content.format_linear'),
                      Icons.menu_book_rounded),
                  SegmentedSliderItem(_Library.interactive,
                      context.tr('content.format_interactive'),
                      Icons.touch_app_rounded),
                  SegmentedSliderItem(_Library.quran,
                      context.tr('content.format_quran'),
                      Icons.auto_stories_rounded),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.tr(showQuran
                      ? 'quran.search_hint'
                      : 'library.search_hint'),
                  prefixIcon: const Icon(Icons.search,
                      color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 12),
              if (showQuran)
                _QuranShelf(query: _searchCtrl.text)
              else ...[
                SoftCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () =>
                            setState(() => _filtersOpen = !_filtersOpen),
                        child: Row(
                          children: [
                            const Icon(Icons.filter_alt_outlined, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              context.tr('library.filters'),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            Icon(
                              _filtersOpen
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                            ),
                          ],
                        ),
                      ),
                      if (_filtersOpen) ...[
                        const SizedBox(height: 14),
                        Text(
                          context.tr('content.filter_by_type'),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.start,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            SoftChip(
                              label: context.tr('common.all'),
                              selected: _type == 'all',
                              onTap: () => setState(() => _type = 'all'),
                            ),
                            SoftChip(
                              label: context.tr('content.filter_audio'),
                              selected: _type == 'audio',
                              onTap: () => setState(() => _type = 'audio'),
                            ),
                            SoftChip(
                              label: context.tr('content.filter_text'),
                              selected: _type == 'text',
                              onTap: () => setState(() => _type = 'text'),
                            ),
                            SoftChip(
                              label: context.tr('content.filter_ai'),
                              selected: _type == 'ai',
                              onTap: () => setState(() => _type = 'ai'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          context.tr('library.age_range'),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.start,
                          spacing: 8,
                          runSpacing: 8,
                          children: _ageRanges.map((a) {
                            return SoftChip(
                              label: a == 'all' ? context.tr('common.all') : a,
                              selected: _ageRange == a,
                              selectedColor: AppColors.softMint,
                              onTap: () => setState(() => _ageRange = a),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          context.tr('content.filter_by_language'),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.start,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            SoftChip(
                              label: context.tr('content.filter_lang_all'),
                              selected: _language == 'all',
                              selectedColor: AppColors.softMint,
                              onTap: () => setState(() => _language = 'all'),
                            ),
                            SoftChip(
                              label: context.tr('content.filter_lang_en'),
                              selected: _language == 'en',
                              selectedColor: AppColors.softMint,
                              onTap: () => setState(() => _language = 'en'),
                            ),
                            SoftChip(
                              label: context.tr('content.filter_lang_ms'),
                              selected: _language == 'ms',
                              selectedColor: AppColors.softMint,
                              onTap: () => setState(() => _language = 'ms'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (_loading) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ] else if (_stories.isEmpty) ...[
                  EmptyState(
                    icon: Icons.menu_book_outlined,
                    title: context.tr('library.no_stories_title'),
                    subtitle: _error != null
                        ? context.tr('library.no_stories_body_error')
                        : context.tr('library.no_stories_body_empty'),
                    iconBackground: AppColors.softPink,
                    iconColor: AppColors.primaryBlueDark,
                  ),
                ] else if (_inFormat.isEmpty) ...[
                  EmptyState(
                    icon: Icons.menu_book_outlined,
                    title: context.tr('library.no_stories_title'),
                    subtitle: context.tr('content.empty_format'),
                    iconBackground: AppColors.softPink,
                    iconColor: AppColors.primaryBlueDark,
                  ),
                ] else if (stories.isEmpty) ...[
                  EmptyState(
                    icon: Icons.search_off_rounded,
                    title: context.tr('library.no_match_title'),
                    subtitle: context.tr('library.no_match_body'),
                    iconBackground: AppColors.softPeach,
                    iconColor: AppColors.warning,
                    action: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _filtersActive ? _clearFilters : null,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(context.tr('library.clear_filters')),
                    ),
                  ),
                ] else ...[
                  Text(
                    '${stories.length} ${context.tr('library.stories_found')}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: stories.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.82,
                    ),
                    itemBuilder: (context, i) {
                      final s = stories[i];
                      return _StoryGridTile(
                        story: s,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AudioPlayerPage(
                              title: s.title,
                              audiobookId: s.audiobookId,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/* The Al-Quran tab: chapters the caregiver has downloaded, ready to play.
   Downloading and removing stay in the caregiver's Content Management. */
class _QuranShelf extends StatefulWidget {
  final String query;
  const _QuranShelf({required this.query});

  @override
  State<_QuranShelf> createState() => _QuranShelfState();
}

class _QuranShelfState extends State<_QuranShelf> {
  final QuranPackService _pack = QuranPackService.instance;

  @override
  void initState() {
    super.initState();
    _pack.init();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _pack,
      builder: (context, _) {
        final m = _pack.manifest;
        if (m == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final installed = m.chapters
            .where((c) => _pack.stateOf(c.number) == QuranChapterState.installed)
            .toList();
        if (installed.isEmpty) {
          return EmptyState(
            icon: Icons.auto_stories_rounded,
            title: context.tr('quran.child_empty_title'),
            subtitle: context.tr('quran.child_empty_body'),
            iconBackground: AppColors.softPink,
            iconColor: AppColors.primaryBlueDark,
          );
        }
        final chapters =
            installed.where((c) => c.matches(widget.query)).toList();
        if (chapters.isEmpty) {
          return EmptyState(
            icon: Icons.search_off_rounded,
            title: context.tr('library.no_match_title'),
            iconBackground: AppColors.softPeach,
            iconColor: AppColors.warning,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in chapters) ...[
              _QuranChapterTile(
                chapter: c,
                gif: _pack.gifFor(c.elementId),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _QuranChapterTile extends StatelessWidget {
  final QuranChapter chapter;
  final File? gif;
  const _QuranChapterTile({required this.chapter, required this.gif});

  @override
  Widget build(BuildContext context) {
    final versesLabel = context
        .tr('quran.verses')
        .replaceAll('{n}', '${chapter.verseCount}');
    return SoftCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => QuranPlayerPage(chapter: chapter)),
      ),
      child: Row(
        children: [
          QuranElementThumb(
            elementId: chapter.elementId,
            gif: gif,
            size: 52,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chapter.nameEn,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${chapter.meaningEn} • $versesLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            chapter.nameAr,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
                fontSize: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.play_circle_outline_rounded,
              color: AppColors.primaryBlueDark),
        ],
      ),
    );
  }
}

class _StoryGridTile extends StatelessWidget {
  final ContentItem story;
  final VoidCallback onTap;
  const _StoryGridTile({required this.story, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ageLabel = (story.ageGroup ?? '').trim().isEmpty
        ? null
        : 'Age ${story.ageGroup}';
    // Same labels as the caregiver's library tiles.
    final typeLabel = story.isGenerated
        ? 'AI'
        : context.tr((story.type ?? '').toLowerCase() == 'audio'
            ? 'content.filter_audio'
            : 'content.filter_text');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CoverArt(
                  imageUrl: story.coverImage,
                  category: story.category,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                story.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (ageLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            AppColors.softPeach.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        ageLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    typeLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverArt extends StatelessWidget {
  final String? imageUrl;
  final String? category;
  const _CoverArt({this.imageUrl, this.category});

  static const _categoryStyle = <String, (Color, String)>{
    'fantasy': (AppColors.softLavender, '🐉'),
    'animals': (AppColors.softMint, '🦊'),
    'nature': (AppColors.softYellow, '🌿'),
    'adventure': (AppColors.softPeach, '⛵'),
    'science': (AppColors.iconCircleBlue, '🤖'),
  };

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          imageUrl!,
          fit: BoxFit.cover,
          width: double.infinity,
          cacheWidth: 500, // grid covers are small; saves memory
          errorBuilder: (_, _, _) => _placeholder(),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return _placeholder(loading: true);
          },
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder({bool loading = false}) {
    final key = (category ?? '').toLowerCase();
    final style = _categoryStyle[key] ?? (AppColors.iconCirclePurple, '📖');
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: style.$1,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: loading
          ? const CircularProgressIndicator()
          : Text(style.$2, style: const TextStyle(fontSize: 48)),
    );
  }
}
