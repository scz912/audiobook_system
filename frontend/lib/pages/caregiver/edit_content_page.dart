import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../i18n/i18n.dart';
import '../../models/audiobook.dart';
import '../../services/database_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/soft_card.dart';
import '../../widgets/soft_chip.dart';

/* Edit screen for an audiobook. The caregiver can change the details
   (title, description, language), edit each page's text and image, and add
   or delete pages. Each part saves on its own, so one failed save doesn't
   lose the rest. */
class EditContentPage extends StatefulWidget {
  final String audiobookId;
  const EditContentPage({super.key, required this.audiobookId});

  @override
  State<EditContentPage> createState() => _EditContentPageState();
}

class _EditContentPageState extends State<EditContentPage> {
  bool _loading = true;
  Audiobook? _audiobook;

  // Details form — text controllers and the chosen language.
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _language = 'en';
  bool _savingMeta = false;

  // One draft per page, holding its text controller and any new image.
  final List<_PageDraft> _pages = [];
  // Pages currently saving / deleting, so their cards show a spinner.
  final Set<String> _savingPages = {};
  final Set<String> _deletingPages = {};
  bool _addingPage = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    for (final p in _pages) {
      p.textCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final resp = await DatabaseService.getAudiobookData(widget.audiobookId);
    if (!mounted) return;
    if (resp.success && resp.data is Audiobook) {
      final book = resp.data as Audiobook;
      _audiobook = book;
      _titleCtrl.text = book.title;
      _descCtrl.text = book.description ?? '';
      _language = (book.language ?? 'en').toLowerCase();
      if (_language != 'en' && _language != 'ms') _language = 'en';
      _pages
        ..clear()
        ..addAll(book.pages.map(_PageDraft.fromExisting));
    } else {
      AppSnackbar.error(resp.message, context: context);
    }
    setState(() => _loading = false);
  }

  // metadata

  Future<void> _saveMetadata() async {
    final patch = <String, dynamic>{};
    final book = _audiobook;
    if (book == null) return;
    final newTitle = _titleCtrl.text.trim();
    if (newTitle.isNotEmpty && newTitle != book.title) {
      patch['title'] = newTitle;
    }
    final newDesc = _descCtrl.text.trim();
    if (newDesc != (book.description ?? '')) {
      patch['description'] = newDesc.isEmpty ? null : newDesc;
    }
    if (_language != (book.language ?? 'en').toLowerCase()) {
      patch['language'] = _language;
    }
    if (patch.isEmpty) return;

    setState(() => _savingMeta = true);
    final resp =
        await DatabaseService.updateContent(widget.audiobookId, patch);
    if (!mounted) return;
    setState(() => _savingMeta = false);
    if (resp.success) {
      // Re-load so any tidying the backend did (trimming, etc.) shows.
      await _load();
      if (mounted) {
        AppSnackbar.success(context.trRead('content.metadata_saved'),
            context: context);
      }
    } else {
      AppSnackbar.error(
        '${context.trRead('content.edit_save_error')}: ${resp.message}',
        context: context,
      );
    }
  }

  // per-page

  Future<void> _pickImageFor(_PageDraft p) async {
    final file =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 88);
    if (file == null || !mounted) return;
    setState(() => p.newImagePath = file.path);
  }

  Future<void> _savePage(_PageDraft p) async {
    final pageId = p.pageId;
    if (pageId == null) return;
    setState(() => _savingPages.add(pageId));
    final resp = await DatabaseService.updateAudiobookPage(
      audiobookId: widget.audiobookId,
      pageId: pageId,
      text: p.textCtrl.text,
      imagePath: p.newImagePath,
    );
    if (!mounted) return;
    setState(() => _savingPages.remove(pageId));
    if (resp.success) {
      // Take the saved values (image URL, etc.) and clear the pending file
      // now that it's uploaded.
      if (resp.data is Map<String, dynamic>) {
        final m = resp.data as Map<String, dynamic>;
        setState(() {
          p.imageUrl = m['image'] as String? ?? p.imageUrl;
          p.newImagePath = null;
        });
      }
      AppSnackbar.success(context.trRead('content.page_saved'),
          context: context);
    } else {
      AppSnackbar.error(
        '${context.trRead('content.edit_save_error')}: ${resp.message}',
        context: context,
      );
    }
  }

  Future<void> _deletePage(_PageDraft p) async {
    final pageId = p.pageId;
    if (pageId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(ctx.tr('content.delete_page_confirm')),
        content: Text(
          ctx.tr('content.delete_page_confirm_body'),
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
            child: Text(ctx.tr('content.delete_page_label')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingPages.add(pageId));
    final resp = await DatabaseService.deleteAudiobookPage(
      audiobookId: widget.audiobookId,
      pageId: pageId,
    );
    if (!mounted) return;
    setState(() => _deletingPages.remove(pageId));
    if (resp.success) {
      setState(() {
        p.textCtrl.dispose();
        _pages.removeWhere((x) => x.pageId == pageId);
      });
    } else {
      AppSnackbar.error(
        '${context.trRead('content.edit_save_error')}: ${resp.message}',
        context: context,
      );
    }
  }

  Future<void> _addPage() async {
    setState(() => _addingPage = true);
    final nextNumber = _pages.isEmpty
        ? 1
        : (_pages.map((p) => p.pageNumber).reduce((a, b) => a > b ? a : b) +
            1);
    final resp = await DatabaseService.addAudiobookPage(
      audiobookId: widget.audiobookId,
      pageNumber: nextNumber,
    );
    if (!mounted) return;
    setState(() => _addingPage = false);
    if (resp.success && resp.data is Map<String, dynamic>) {
      final m = resp.data as Map<String, dynamic>;
      setState(() {
        _pages.add(_PageDraft(
          pageId: m['page_id'] as String?,
          pageNumber: (m['page_number'] as int?) ?? nextNumber,
          textCtrl: TextEditingController(text: (m['text'] as String?) ?? ''),
          imageUrl: m['image'] as String?,
        ));
      });
    } else {
      AppSnackbar.error(
        '${context.trRead('content.edit_save_error')}: ${resp.message}',
        context: context,
      );
    }
  }

  // build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  BackPill(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('content.edit_screen_title'),
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  _MetadataCard(
                    titleCtrl: _titleCtrl,
                    descCtrl: _descCtrl,
                    language: _language,
                    saving: _savingMeta,
                    onLanguageChanged: (v) => setState(() => _language = v),
                    onSave: _saveMetadata,
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('content.pages_section'),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        '${_pages.length}',
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_pages.isEmpty)
                    SoftCard(
                      child: Text(
                        context.tr('content.no_pages_yet'),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    )
                  else
                    for (final p in _pages) ...[
                      _PageEditor(
                        draft: p,
                        saving: p.pageId != null &&
                            _savingPages.contains(p.pageId),
                        deleting: p.pageId != null &&
                            _deletingPages.contains(p.pageId),
                        onPickImage: () => _pickImageFor(p),
                        onSave: () => _savePage(p),
                        onDelete: () => _deletePage(p),
                      ),
                      const SizedBox(height: 12),
                    ],
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: _addingPage ? null : _addPage,
                    icon: _addingPage
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_rounded, size: 18),
                    label: Text(context.tr('content.add_page')),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/* Top card with the book's title, description, and language, plus its own
   save button — so details can be edited without touching the pages. */
class _MetadataCard extends StatelessWidget {
  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final String language;
  final bool saving;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback onSave;
  const _MetadataCard({
    required this.titleCtrl,
    required this.descCtrl,
    required this.language,
    required this.saving,
    required this.onLanguageChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('content.metadata_section'),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            controller: titleCtrl,
            maxLength: 255,
            decoration: InputDecoration(
              labelText: context.tr('content.field_title'),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: descCtrl,
            maxLines: 3,
            minLines: 2,
            decoration: InputDecoration(
              labelText: context.tr('content.field_description'),
            ),
          ),
          const SizedBox(height: 12),
          Text(context.tr('content.field_language'),
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              SoftChip(
                label: context.tr('content.filter_lang_en'),
                selected: language == 'en',
                selectedColor: AppColors.softMint,
                onTap: () => onLanguageChanged('en'),
              ),
              SoftChip(
                label: context.tr('content.filter_lang_ms'),
                selected: language == 'ms',
                selectedColor: AppColors.softMint,
                onTap: () => onLanguageChanged('ms'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(context.tr('content.save_metadata')),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* One editable page card: image and change-image button up top, text field
   in the middle, save + delete at the bottom. Shows a spinner while saving
   or deleting. */
class _PageEditor extends StatelessWidget {
  final _PageDraft draft;
  final bool saving;
  final bool deleting;
  final VoidCallback onPickImage;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  const _PageEditor({
    required this.draft,
    required this.saving,
    required this.deleting,
    required this.onPickImage,
    required this.onSave,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final pageLabel = context
        .tr('content.page_number')
        .replaceAll('{n}', draft.pageNumber.toString());
    final hasNewImage = draft.newImagePath != null;
    final hasExistingImage =
        draft.imageUrl != null && draft.imageUrl!.isNotEmpty;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pageLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              if (deleting)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  tooltip: context.tr('content.delete_page_label'),
                  onPressed: saving ? null : onDelete,
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.danger),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PageImageThumb(
                newImagePath: draft.newImagePath,
                imageUrl: draft.imageUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasNewImage || hasExistingImage
                          ? context.tr('content.change_image')
                          : context.tr('content.no_image'),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: saving || deleting ? null : onPickImage,
                      icon: const Icon(Icons.image_outlined, size: 16),
                      label: Text(context.tr('content.change_image')),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: draft.textCtrl,
            maxLines: 4,
            minLines: 3,
            enabled: !saving && !deleting,
            decoration: InputDecoration(
              labelText: context.tr('content.page_text'),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: saving || deleting ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(context.tr('content.save_page')),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* 64×64 page image preview. Shows the newly-picked file first (so the
   change is visible before saving), then the saved image, then a
   placeholder. */
class _PageImageThumb extends StatelessWidget {
  final String? newImagePath;
  final String? imageUrl;
  const _PageImageThumb({this.newImagePath, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final newPath = newImagePath;
    final url = imageUrl;
    Widget content;
    if (newPath != null) {
      // A just-picked file, not uploaded yet — preview it from a file://
      // URL so we don't need dart:io here.
      content = Image.network(
        Uri.file(newPath).toString(),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    } else if (url != null && url.isNotEmpty) {
      // CachedNetworkImage keeps a disk copy so reopening the edit screen
      // is instant and doesn't re-download every page.
      content = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        memCacheWidth: 200,
        placeholder: (_, _) => _placeholder(),
        errorWidget: (_, _, _) => _placeholder(),
        fadeInDuration: const Duration(milliseconds: 120),
        fadeOutDuration: Duration.zero,
      );
    } else {
      content = _placeholder();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: 64, height: 64, child: content),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.softLavender,
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined,
            color: AppColors.textPrimary, size: 24),
      );
}

/* A working copy of one page being edited. Has its own text controller so
   typing doesn't rebuild the whole list, plus slots for the saved image URL
   and a just-picked file not yet uploaded. */
class _PageDraft {
  final String? pageId;
  final int pageNumber;
  final TextEditingController textCtrl;
  String? imageUrl;
  String? newImagePath;
  int? audioStartMs;

  _PageDraft({
    required this.pageId,
    required this.pageNumber,
    required this.textCtrl,
    this.imageUrl,
    this.audioStartMs,
  });

  factory _PageDraft.fromExisting(AudiobookPage p) {
    return _PageDraft(
      pageId: p.pageId,
      pageNumber: p.pageNumber,
      textCtrl: TextEditingController(text: p.text ?? ''),
      imageUrl: p.image,
      audioStartMs: p.audioStartMs,
    );
  }
}
