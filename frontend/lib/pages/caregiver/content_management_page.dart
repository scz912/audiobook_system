import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../models/content_item.dart';
import '../../models/content_summary.dart';
import '../../services/api_service.dart';
import '../../services/database_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/soft_chip.dart';
import '../../widgets/stat_card.dart';
import '../child/audio_player_page.dart';
import 'edit_content_page.dart';
import 'upload_content_page.dart';

class ContentManagementPage extends StatefulWidget {
  /* Called when the header back arrow is tapped. The shell uses it to go
     back to the Dashboard tab, since pop() doesn't work for a tab body. */
  final VoidCallback? onBack;
  const ContentManagementPage({super.key, this.onBack});

  @override
  State<ContentManagementPage> createState() => _ContentManagementPageState();
}

class _ContentManagementPageState extends State<ContentManagementPage> {
  ContentSummary _summary = ContentSummary.empty();
  List<ContentItem> _items = const [];
  bool _loading = false;
  String _filter = 'all';
  String _langFilter = 'all'; // 'all' | 'en' | 'ms'
  final TextEditingController _searchCtrl = TextEditingController();

  // While a book is still generating, keep re-checking until it's done.
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final ApiResponse summaryResp = await DatabaseService.getContentSummary();
    final ApiResponse listResp = await DatabaseService.getContentList(
      filterType: _filter == 'all' ? null : _filter,
      search: _searchCtrl.text.trim(),
      language: _langFilter == 'all' ? null : _langFilter,
    );

    final summary = summaryResp.success && summaryResp.data is ContentSummary
        ? summaryResp.data as ContentSummary
        : ContentSummary.empty();

    final rawItems = listResp.success && listResp.data is List<ContentItem>
        ? listResp.data as List<ContentItem>
        : <ContentItem>[];

    if (!mounted) return;
    setState(() {
      _summary = summary;
      _items = rawItems;
      _loading = false;
    });
    _syncPolling();
  }

  Future<void> _editItem(ContentItem item) async {
    final id = item.audiobookId;
    if (id == null || id.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditContentPage(audiobookId: id)),
    );
    // Always refresh on return — the title, pages, or images may have changed.
    if (mounted) await _refresh(silent: true);
  }

  Future<void> _deleteItem(ContentItem item) async {
    final id = item.audiobookId;
    if (id == null || id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(ctx.tr('content.delete_confirm')),
        content: Text(
          ctx.tr('content.delete_confirm_body'),
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
            child: Text(ctx.tr('content.delete_button')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final resp = await DatabaseService.deleteContent(id);
    if (!mounted) return;
    if (resp.success) {
      await _refresh(silent: true);
    } else {
      AppSnackbar.error(
        '${context.trRead('content.delete_error')}: ${resp.message}',
        context: context,
      );
    }
  }

  /* Open the book in the same player the child uses, so the caregiver sees
     and hears exactly what the child will. */
  void _openPreview(ContentItem item) {
    if (item.status == 'processing') {
      AppSnackbar.info(
        context.trRead('content.preview_still_generating'),
        context: context,
      );
      return;
    }
    final id = item.audiobookId;
    if (id == null || id.isEmpty) {
      AppSnackbar.warning(context.trRead('content.preview_no_book'),
          context: context);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AudioPlayerPage(title: item.title, audiobookId: id, previewMode: true),
      ),
    );
  }

  /* Check every few seconds while a book is generating, and stop once all
     are done — so new books appear without a pull-to-refresh. */
  void _syncPolling() {
    final stillGenerating = _items.any((i) => i.status == 'processing');
    if (stillGenerating) {
      _pollTimer ??= Timer.periodic(
        const Duration(seconds: 5),
        (_) => _refresh(silent: true),
      );
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          BackPill(
            label: 'Back to Dashboard',
            onTap: widget.onBack ?? () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('content.title'),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  // After the upload page closes, refresh so the new book
                  // shows up right away.
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const UploadContentPage()),
                  );
                  if (mounted) await _refresh();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.upload, size: 18),
                label: Text(context.tr('common.upload')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('content.subtitle'),
            style:
                const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 18),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.2,
            children: [
              StatCard(icon: Icons.menu_book_outlined, iconBackground: AppColors.iconCircleBlue, value: '${_summary.totalItems}', label: context.tr('content.total_items')),
              StatCard(icon: Icons.headphones_outlined, iconBackground: AppColors.iconCircleGreen, value: '${_summary.audioFiles}', label: context.tr('content.audio_files')),
              StatCard(icon: Icons.description_outlined, iconBackground: AppColors.iconCirclePeach, value: '${_summary.textFiles}', label: context.tr('content.text_files')),
              StatCard(icon: Icons.auto_awesome, iconBackground: AppColors.iconCirclePurple, value: '${_summary.aiGenerated}', label: context.tr('content.ai_generated')),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchCtrl,
            onSubmitted: (_) => _refresh(),
            decoration: InputDecoration(
              hintText: context.tr('content.search_hint'),
              prefixIcon:
                  const Icon(Icons.search, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.filter_alt_outlined,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(context.tr('content.filter_by_type'),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftChip(label: context.tr('common.all'), selected: _filter == 'all', onTap: () { setState(() => _filter = 'all'); _refresh(); }),
              SoftChip(label: context.tr('content.filter_audio'), selected: _filter == 'audio', onTap: () { setState(() => _filter = 'audio'); _refresh(); }),
              SoftChip(label: context.tr('content.filter_text'), selected: _filter == 'text', onTap: () { setState(() => _filter = 'text'); _refresh(); }),
              SoftChip(label: context.tr('content.filter_ai'), selected: _filter == 'ai', onTap: () { setState(() => _filter = 'ai'); _refresh(); }),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.translate,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(context.tr('content.filter_by_language'),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftChip(
                label: context.tr('content.filter_lang_all'),
                selected: _langFilter == 'all',
                onTap: () {
                  setState(() => _langFilter = 'all');
                  _refresh();
                },
              ),
              SoftChip(
                label: context.tr('content.filter_lang_en'),
                selected: _langFilter == 'en',
                selectedColor: AppColors.softMint,
                onTap: () {
                  setState(() => _langFilter = 'en');
                  _refresh();
                },
              ),
              SoftChip(
                label: context.tr('content.filter_lang_ms'),
                selected: _langFilter == 'ms',
                selectedColor: AppColors.softMint,
                onTap: () {
                  setState(() => _langFilter = 'ms');
                  _refresh();
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final item in _items) ...[
              _ContentTile(
                item: item,
                onTap: () => _openPreview(item),
                onEdit: () => _editItem(item),
                onDelete: () => _deleteItem(item),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _ContentTile extends StatelessWidget {
  final ContentItem item;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _ContentTile({
    required this.item,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  static ({IconData icon, Color bg, String label}) _typeMetaFor(ContentItem item) {
    if (item.isGenerated) {
      return (icon: Icons.auto_awesome, bg: AppColors.iconCirclePurple, label: 'AI');
    }
    final type = (item.type ?? '').toLowerCase();
    if (type == 'audio') {
      return (icon: Icons.headphones_outlined, bg: AppColors.iconCircleGreen, label: 'Audio');
    }
    return (icon: Icons.description_outlined, bg: AppColors.iconCirclePeach, label: 'Text');
  }

  @override
  Widget build(BuildContext context) {
    final meta = _typeMetaFor(item);
    final processing = item.status == 'processing';
    final showMenu =
        !processing && (onEdit != null || onDelete != null);
    // Resolve the menu labels here, in the widget tree. PopupMenuButton's
    // itemBuilder runs in an overlay where ctx.tr(...) can't reach the
    // Provider and would throw, stopping the menu from opening.
    final editLabel = context.tr('content.edit_label');
    final deleteLabel = context.tr('content.delete_label');
    final tapToPreviewLabel = context.tr('content.tap_to_preview');

    // Material is the card surface. The InkWell wraps only the left preview
    // area so it can't steal taps from the menu, which sits beside it as a
    // separate Row child.
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
                padding: EdgeInsets.fromLTRB(18, 18, showMenu ? 4 : 18, 18),
                child: Row(
                  children: [
                    _Thumbnail(
                      imageUrl: item.coverImage,
                      meta: meta,
                      processing: processing,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          if (item.topic != null || item.difficulty != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                [item.topic, item.difficulty]
                                    .whereType<String>()
                                    .join(' • '),
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13),
                              ),
                            ),
                          if (!processing)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.play_circle_outline,
                                      size: 15,
                                      color: AppColors.primaryBlueDark),
                                  const SizedBox(width: 4),
                                  Text(
                                    tapToPreviewLabel,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primaryBlueDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    processing ? _generatingBadge(context) : _typeBadge(meta),
                  ],
                ),
              ),
            ),
          ),
          if (showMenu)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: PopupMenuButton<String>(
                tooltip: '',
                icon: const Icon(Icons.more_vert_rounded,
                    color: AppColors.textSecondary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onSelected: (action) {
                  if (action == 'edit') {
                    onEdit?.call();
                  } else if (action == 'delete') {
                    onDelete?.call();
                  }
                },
                itemBuilder: (_) => [
                  if (onEdit != null)
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          const Icon(Icons.edit_rounded, size: 18),
                          const SizedBox(width: 10),
                          Text(editLabel),
                        ],
                      ),
                    ),
                  if (onDelete != null)
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline_rounded,
                              size: 18, color: AppColors.danger),
                          const SizedBox(width: 10),
                          Text(deleteLabel,
                              style:
                                  const TextStyle(color: AppColors.danger)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _typeBadge(({IconData icon, Color bg, String label}) meta) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: meta.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(meta.label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  Widget _generatingBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.softPeach,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 6),
          Text(context.tr('content.generating'),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

/* Thumbnail for a content row: the cover image if there is one,
   otherwise a coloured circle with the content-type icon. */
class _Thumbnail extends StatelessWidget {
  final String? imageUrl;
  final ({IconData icon, Color bg, String label}) meta;
  final bool processing;
  const _Thumbnail({
    required this.imageUrl,
    required this.meta,
    this.processing = false,
  });

  @override
  Widget build(BuildContext context) {
    // No cover yet while generating — show a spinner.
    if (processing) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.softPeach,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        // CachedNetworkImage keeps a disk copy so scrolling the list
        // doesn't re-download thumbnails. Tiny memCacheWidth saves RAM
        // since these are 48x48 on screen.
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          memCacheWidth: 150,
          errorWidget: (_, _, _) => _iconCircle(),
          placeholder: (_, _) => Container(
            decoration: BoxDecoration(
              color: meta.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          fadeInDuration: const Duration(milliseconds: 120),
          fadeOutDuration: Duration.zero,
        ),
      );
    }
    return _iconCircle();
  }

  Widget _iconCircle() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: meta.bg, shape: BoxShape.circle),
      child: Icon(meta.icon, size: 20, color: AppColors.textPrimary),
    );
  }
}

