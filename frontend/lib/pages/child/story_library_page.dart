import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../models/content_item.dart';
import '../../models/quran.dart';
import '../../services/api_service.dart';
import '../../services/database_service.dart';
import '../../services/quran_pack_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/quran_element_thumb.dart';
import '../../widgets/segmented_slider.dart';
import '../../widgets/soft_card.dart';
import '../../widgets/shelf_nav_bar.dart';
import 'audio_player_page.dart';
import 'quran_player_page.dart';
import '../../widgets/whole_words_text.dart';

/* The same three kinds of audiobook as the caregiver's Content Management
   slider. */
enum StoryShelf { linear, interactive, quran }

class StoryLibraryPage extends StatefulWidget {
  /* Optional back-arrow override. As a tab body, ChildShell passes a
     callback to go to the Home tab. When pushed as a normal route this is
     null and Navigator.maybePop() is used. */
  final VoidCallback? onBack;
  // Lets a guide switch the shelf (Linear / Interactive / Al-Quran).
  final ValueListenable<StoryShelf>? shelf;
  /* Adds a "Create" tile after the books, for accounts that make their own
     (not Child Mode). Opens the editor for the shelf's format. */
  final Future<void> Function(StoryShelf format)? onCreate;
  const StoryLibraryPage({super.key, this.onBack, this.shelf, this.onCreate});

  @override
  State<StoryLibraryPage> createState() => _StoryLibraryPageState();
}

class _StoryLibraryPageState extends State<StoryLibraryPage> {
  StoryShelf _library = StoryShelf.linear;

  List<ContentItem> _stories = const [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    final shelf = widget.shelf;
    if (shelf != null) {
      _library = shelf.value;
      shelf.addListener(_followShelf);
    }
    _loadStories();
  }

  @override
  void dispose() {
    widget.shelf?.removeListener(_followShelf);
    _pollTimer?.cancel();
    super.dispose();
  }

  void _followShelf() {
    final shelf = widget.shelf;
    if (shelf != null && mounted) setState(() => _library = shelf.value);
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

  /* Finished books of the selected format. Books still generating pictures
     stay hidden. No filters or search box: they were too much reading for
     the children, and the caregiver already chooses what's in the library. */
  List<ContentItem> get _inFormat => _stories
      .where((s) => s.status != 'processing' && s.bookFormat == _library.name)
      .toList();

  Future<void> _create() async {
    final onCreate = widget.onCreate;
    if (onCreate == null) return;
    await onCreate(_library);
    // A new book (or one still making pictures) shows up straight away.
    if (mounted) await _loadStories(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final stories = _inFormat;
    final canCreate = widget.onCreate != null;
    final showQuran = _library == StoryShelf.quran;
    return Scaffold(
      // As a Child Mode tab (it has onBack there) the taskbar's dyed
      // background shows through; as its own page it has the usual one.
      backgroundColor: widget.onBack != null ? Colors.transparent : AppColors.background,
      /* The page runs on behind the shelf (it's see-through there), as on
         the caregiver's pages; shelfBottomSpace() below keeps the last row
         clear of it. */
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadStories,
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 12, 20, shelfBottomSpace(context)),
            children: [
              BackPill(onTap: widget.onBack ?? () => Navigator.of(context).maybePop()),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: WholeWordsText(
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
              const SizedBox(height: 16),
              // Pictures only for the children: a storybook, a puzzle piece
              // for the stories that ask questions, and a mosque for the
              // Quran. The words stay as screen-reader labels.
              SegmentedSlider<StoryShelf>(
                value: _library,
                height: 64,
                onChanged: (l) => setState(() => _library = l),
                items: [
                  SegmentedSliderItem.emoji(StoryShelf.linear,
                      context.tr('content.format_linear'), '📖'),
                  SegmentedSliderItem.emoji(StoryShelf.interactive,
                      context.tr('content.format_interactive'), '🧩'),
                  SegmentedSliderItem.emoji(StoryShelf.quran,
                      context.tr('content.format_quran'), '🕌'),
                ],
              ),
              const SizedBox(height: 16),
              if (showQuran)
                const _QuranShelf()
              else if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: context.tr('library.no_stories_title'),
                  subtitle: context.tr('library.no_stories_body_error'),
                  iconBackground: AppColors.softPink,
                  iconColor: AppColors.primaryBlueDark,
                )
              else if (stories.isEmpty && !canCreate)
                EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: context.tr('library.no_stories_title'),
                  iconBackground: AppColors.softPink,
                  iconColor: AppColors.primaryBlueDark,
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: stories.length + (canCreate ? 1 : 0),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemBuilder: (context, i) {
                    if (i == stories.length) return _CreateTile(onTap: _create);
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
          ),
        ),
      ),
    );
  }
}

/* Every chapter (surah) of the Al-Quran pack. Nothing downloads by itself:
   a chapter that isn't on the device shows a download button, which asks
   first (with the size) before fetching it. */
class _QuranShelf extends StatefulWidget {
  const _QuranShelf();

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

  Future<void> _tap(QuranChapter c) async {
    switch (_pack.stateOf(c.number)) {
      case QuranChapterState.installed:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => QuranPlayerPage(chapter: c)),
        );
      case QuranChapterState.notDownloaded:
      case QuranChapterState.failed:
        if (await _askDownload(c)) await _pack.download(c.number);
      case QuranChapterState.queued:
      case QuranChapterState.downloading:
      case QuranChapterState.installing:
        break;
    }
  }

  // A short, mostly-pictures question: download this chapter (and its size)?
  Future<bool> _askDownload(QuranChapter c) async {
    final size = QuranPackService.formatBytes(_pack.downloadBytesFor(c));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const CircleAvatar(
          radius: 32,
          backgroundColor: AppColors.softPink,
          child: Icon(Icons.download_rounded, size: 36, color: AppColors.primaryBlueDark),
        ),
        title: Text(
          ctx.tr('quran.download_chapter_confirm').replaceAll('{name}', c.nameEn),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sd_storage_rounded, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(size,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          IconButton.filledTonal(
            tooltip: ctx.tr('common.cancel'),
            iconSize: 32,
            onPressed: () => Navigator.of(ctx).pop(false),
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 12),
          IconButton.filled(
            tooltip: ctx.tr('quran.download'),
            iconSize: 32,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
    );
    return ok == true;
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in m.chapters) ...[
              _QuranChapterTile(
                chapter: c,
                gif: _pack.gifFor(c.elementId),
                state: _pack.stateOf(c.number),
                progress: _pack.progressOf(c.number),
                onTap: () => _tap(c),
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
  final QuranChapterState state;
  final double progress;
  final VoidCallback onTap;
  const _QuranChapterTile({
    required this.chapter,
    required this.gif,
    required this.state,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final installed = state == QuranChapterState.installed;
    return SoftCard(
      onTap: onTap,
      child: Row(
        children: [
          QuranElementThumb(
            elementId: chapter.elementId,
            gif: gif,
            size: 56,
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
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: installed ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  chapter.nameAr,
                  textDirection: TextDirection.rtl,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 17, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox.square(dimension: 52, child: _status()),
        ],
      ),
    );
  }

  // One big picture for where the chapter is: play, download, or progress.
  Widget _status() {
    switch (state) {
      case QuranChapterState.installed:
        return const Icon(Icons.play_circle_fill_rounded,
            size: 52, color: AppColors.primaryBlueDark);
      case QuranChapterState.notDownloaded:
        return const Icon(Icons.download_for_offline_rounded,
            size: 52, color: AppColors.success);
      case QuranChapterState.failed:
        return const Icon(Icons.refresh_rounded, size: 44, color: AppColors.danger);
      case QuranChapterState.queued:
      case QuranChapterState.downloading:
      case QuranChapterState.installing:
        return Padding(
          padding: const EdgeInsets.all(8),
          child: CircularProgressIndicator(
            strokeWidth: 5,
            value: state == QuranChapterState.downloading && progress > 0 ? progress : null,
            color: AppColors.success,
            backgroundColor: AppColors.cardBorder,
          ),
        );
    }
  }
}

class _StoryGridTile extends StatelessWidget {
  final ContentItem story;
  final VoidCallback onTap;
  const _StoryGridTile({required this.story, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Just the cover and the title: no age or type labels to read.
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
              MarqueeText(
                story.title,
                maxLines: 2,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* The last tile on the shelf: a big plus to make a new book. */
class _CreateTile extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = context.tr('library.create');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primaryBlueDark, width: 2.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryBlueDark,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_rounded, size: 48, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: AppColors.primaryBlueDark,
                  ),
                ),
              ],
            ),
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
