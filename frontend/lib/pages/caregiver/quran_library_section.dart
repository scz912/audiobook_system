import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/quran.dart';
import '../../services/quran_pack_service.dart';
import '../../state/language_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/quran_element_thumb.dart';
import '../../widgets/soft_card.dart';
import '../child/quran_player_page.dart';

/* The "Al-Quran" tab of Content Management: the downloadable recitation
   pack. Each chapter (surah) is one item; caregivers download only the
   chapters they want, see how much space each takes, and remove them
   again. The list ends with the sources and licences of everything used. */
class QuranLibrarySection extends StatefulWidget {
  const QuranLibrarySection({super.key});

  @override
  State<QuranLibrarySection> createState() => _QuranLibrarySectionState();
}

class _QuranLibrarySectionState extends State<QuranLibrarySection> {
  final QuranPackService _pack = QuranPackService.instance;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _pack.init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _fill(String template, Map<String, Object> values) {
    var out = template;
    values.forEach((k, v) => out = out.replaceAll('{$k}', '$v'));
    return out;
  }

  List<QuranChapter> _visibleChapters(QuranManifest m) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return m.chapters;
    return m.chapters.where((c) {
      return '${c.number}' == q ||
          c.nameEn.toLowerCase().contains(q) ||
          c.meaningEn.toLowerCase().contains(q) ||
          c.nameAr.contains(q);
    }).toList();
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: Text(body,
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  destructive ? AppColors.danger : AppColors.primaryBlueDark,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _downloadAll() async {
    final size = QuranPackService.formatBytes(_pack.remainingDownloadBytes);
    final ok = await _confirm(
      title: context.trRead('quran.download_all_confirm'),
      body: _fill(context.trRead('quran.download_all_body'), {'size': size}),
      action: context.trRead('quran.download'),
    );
    if (ok) await _pack.downloadAll();
  }

  Future<void> _removeAll() async {
    final size = QuranPackService.formatBytes(_pack.installedBytes);
    final ok = await _confirm(
      title: context.trRead('quran.remove_all_confirm'),
      body: _fill(context.trRead('quran.remove_all_body'), {'size': size}),
      action: context.trRead('quran.remove'),
      destructive: true,
    );
    if (ok) await _pack.deleteAll();
  }

  Future<void> _downloadChapter(QuranChapter c) async {
    final ok = await _confirm(
      title: _fill(context.trRead('quran.download_chapter_confirm'),
          {'name': c.nameEn}),
      body: _fill(context.trRead('quran.download_chapter_body'), {
        'size': QuranPackService.formatBytes(_pack.downloadBytesFor(c)),
        'verses': c.verseCount,
      }),
      action: context.trRead('quran.download'),
    );
    if (ok) await _pack.download(c.number);
  }

  Future<void> _removeChapter(QuranChapter c) async {
    final ok = await _confirm(
      title: _fill(context.trRead('quran.remove_confirm'), {'name': c.nameEn}),
      body: _fill(context.trRead('quran.remove_body'),
          {'size': QuranPackService.formatBytes(c.installedBytes)}),
      action: context.trRead('quran.remove'),
      destructive: true,
    );
    if (ok) await _pack.delete(c.number);
  }

  void _openChapter(QuranChapter c) {
    switch (_pack.stateOf(c.number)) {
      case QuranChapterState.installed:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => QuranPlayerPage(chapter: c)),
        );
      case QuranChapterState.notDownloaded:
      case QuranChapterState.failed:
        _downloadChapter(c);
      case QuranChapterState.queued:
      case QuranChapterState.downloading:
      case QuranChapterState.installing:
        AppSnackbar.info(context.trRead('quran.still_downloading'),
            context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageState>().code;
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
        final chapters = _visibleChapters(m);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPackCard(m),
            const SizedBox(height: 14),
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: context.tr('quran.search_hint'),
                prefixIcon:
                    const Icon(Icons.search, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 14),
            for (final c in chapters) ...[
              _ChapterTile(
                chapter: c,
                element: m.elementById(c.elementId),
                languageCode: lang,
                state: _pack.stateOf(c.number),
                progress: _pack.progressOf(c.number),
                gif: _pack.gifFor(c.elementId),
                downloadBytes: _pack.downloadBytesFor(c),
                onTap: () => _openChapter(c),
                onDownload: () => _pack.download(c.number),
                onCancel: () => _pack.cancel(c.number),
                onRemove: () => _removeChapter(c),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
            _SourcesCard(manifest: m, languageCode: lang),
          ],
        );
      },
    );
  }

  Widget _buildPackCard(QuranManifest m) {
    final installed = _pack.installedCount;
    final total = m.chapters.length;
    final remaining = _pack.remainingDownloadBytes;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.iconCircleGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.menu_book_rounded,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('quran.pack_title'),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      _fill(context.tr('quran.pack_summary'), {
                        'chapters': total,
                        'verses': m.totalVerses,
                        'reciter': m.reciter,
                      }),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _PackStat(
                label: context.tr('quran.downloaded'),
                value: '$installed / $total',
              ),
              _PackStat(
                label: context.tr('quran.on_device'),
                value: QuranPackService.formatBytes(_pack.installedBytes),
              ),
              _PackStat(
                label: context.tr('quran.full_size'),
                value: QuranPackService.formatBytes(m.totalDownloadBytes),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: installed / total,
                minHeight: 8,
                backgroundColor: AppColors.cardBorder,
                valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.softMintDark),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_pack.isBusy)
                FilledButton.icon(
                  onPressed: _pack.cancelAll,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.softPeach,
                    foregroundColor: AppColors.textPrimary,
                  ),
                  icon: const Icon(Icons.pause_circle_outline, size: 18),
                  label: Text(context.tr('quran.stop_downloads')),
                )
              else if (remaining > 0)
                FilledButton.icon(
                  onPressed: _downloadAll,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: AppColors.textPrimary,
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(_fill(context.tr('quran.download_all'),
                      {'size': QuranPackService.formatBytes(remaining)})),
                ),
              if (installed > 0)
                OutlinedButton.icon(
                  onPressed: _removeAll,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(context.tr('quran.remove_all')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PackStat extends StatelessWidget {
  final String label;
  final String value;
  const _PackStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  final QuranChapter chapter;
  final QuranElement? element;
  final String languageCode;
  final QuranChapterState state;
  final double progress;
  final File? gif;
  final int downloadBytes;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onRemove;

  const _ChapterTile({
    required this.chapter,
    required this.element,
    required this.languageCode,
    required this.state,
    required this.progress,
    required this.gif,
    required this.downloadBytes,
    required this.onTap,
    required this.onDownload,
    required this.onCancel,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final installed = state == QuranChapterState.installed;
    final sizeLabel = QuranPackService.formatBytes(
        installed ? chapter.installedBytes : downloadBytes);
    final versesLabel = context
        .tr('quran.verses')
        .replaceAll('{n}', '${chapter.verseCount}');
    // Resolve menu labels here: PopupMenuButton's itemBuilder runs in an
    // overlay where context.tr can't reach the Provider.
    final playLabel = context.tr('quran.play');
    final removeLabel = context.tr('quran.remove_chapter');

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        QuranElementThumb(
                          elementId: chapter.elementId,
                          gif: gif,
                          size: 52,
                        ),
                        Positioned(
                          left: -4,
                          top: -4,
                          child: _NumberBadge(number: chapter.number),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  chapter.nameEn,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                chapter.nameAr,
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(
                                    fontSize: 16,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${chapter.meaningEn} • $versesLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          _statusLine(context, sizeLabel),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _trailing(context, playLabel, removeLabel),
          ),
        ],
      ),
    );
  }

  Widget _statusLine(BuildContext context, String sizeLabel) {
    final visual = quranElementVisual(chapter.elementId);
    final elementChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: visual.color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: 13, color: AppColors.textPrimary),
          const SizedBox(width: 4),
          Text(element?.name(languageCode) ?? chapter.elementId,
              style:
                  const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );

    switch (state) {
      case QuranChapterState.downloading:
        return Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppColors.cardBorder,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primaryBlueDark),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
                context
                    .tr('quran.progress')
                    .replaceAll('{pct}', '${(progress * 100).round()}')
                    .replaceAll('{size}', sizeLabel),
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.textSecondary)),
          ],
        );
      case QuranChapterState.queued:
      case QuranChapterState.installing:
        return Text(
          context.tr(state == QuranChapterState.queued
              ? 'quran.queued'
              : 'quran.installing'),
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary),
        );
      case QuranChapterState.failed:
        return Text(context.tr('quran.failed'),
            style: const TextStyle(
                fontSize: 12,
                color: AppColors.danger,
                fontWeight: FontWeight.w600));
      case QuranChapterState.installed:
      case QuranChapterState.notDownloaded:
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            elementChip,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  state == QuranChapterState.installed
                      ? Icons.check_circle_rounded
                      : Icons.cloud_download_outlined,
                  size: 14,
                  color: state == QuranChapterState.installed
                      ? AppColors.success
                      : AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(sizeLabel,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ],
        );
    }
  }

  Widget _trailing(
      BuildContext context, String playLabel, String removeLabel) {
    switch (state) {
      case QuranChapterState.notDownloaded:
      case QuranChapterState.failed:
        return IconButton(
          tooltip: context.tr('quran.download'),
          icon: Icon(
            state == QuranChapterState.failed
                ? Icons.refresh_rounded
                : Icons.download_rounded,
            color: AppColors.primaryBlueDark,
          ),
          onPressed: onDownload,
        );
      case QuranChapterState.queued:
      case QuranChapterState.downloading:
        return IconButton(
          tooltip: context.tr('quran.cancel'),
          icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
          onPressed: onCancel,
        );
      case QuranChapterState.installing:
        return const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case QuranChapterState.installed:
        return PopupMenuButton<String>(
          tooltip: '',
          icon: const Icon(Icons.more_vert_rounded,
              color: AppColors.textSecondary),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (action) {
            if (action == 'play') onTap();
            if (action == 'remove') onRemove();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'play',
              child: Row(
                children: [
                  const Icon(Icons.play_arrow_rounded, size: 18),
                  const SizedBox(width: 10),
                  Text(playLabel),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'remove',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppColors.danger),
                  const SizedBox(width: 10),
                  Text(removeLabel,
                      style: const TextStyle(color: AppColors.danger)),
                ],
              ),
            ),
          ],
        );
    }
  }
}

class _NumberBadge extends StatelessWidget {
  final int number;
  const _NumberBadge({required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.cardBorder),
      ),
      alignment: Alignment.center,
      child: Text('$number',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

/* Where the recitation, text and GIFs come from, with their
   licences. Required by the Tanzil text licence and the GIFs' CC licences. */
class _SourcesCard extends StatelessWidget {
  final QuranManifest manifest;
  final String languageCode;
  const _SourcesCard({required this.manifest, required this.languageCode});

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(
        color: AppColors.textSecondary, fontSize: 12, height: 1.45);
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: AppColors.primaryBlueDark),
              const SizedBox(width: 8),
              Text(context.tr('quran.sources_title'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(context.tr('quran.sources_note'), style: small),
          const SizedBox(height: 12),
          for (final s in manifest.sources) ...[
            Text(s.title,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
            if (s.detail.isNotEmpty) Text(s.detail, style: small),
            if (s.license.isNotEmpty) Text(s.license, style: small),
            if (s.url.isNotEmpty)
              SelectableText(s.url,
                  style: const TextStyle(
                      color: AppColors.primaryBlueDark, fontSize: 12)),
            const SizedBox(height: 10),
          ],
          const Divider(height: 18),
          Text(context.tr('quran.nature_scenes'),
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final e in manifest.elements) ...[
            Text('${e.name(languageCode)} — ${e.credit} (${e.license})',
                style: small),
            SelectableText(e.sourceUrl,
                style: const TextStyle(
                    color: AppColors.primaryBlueDark, fontSize: 12)),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}
