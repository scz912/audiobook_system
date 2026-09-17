import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/content_item.dart';
import '../../services/database_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/soft_card.dart';

// Pick one of my audiobooks and share it to the hub.
class ShareToHubPage extends StatefulWidget {
  const ShareToHubPage({super.key});

  @override
  State<ShareToHubPage> createState() => _ShareToHubPageState();
}

class _ShareToHubPageState extends State<ShareToHubPage> {
  final _captionCtrl = TextEditingController();
  List<ContentItem> _books = const [];
  ContentItem? _selected;
  bool _includeMusic = false;
  bool _loading = true;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBooks() async {
    final resp = await DatabaseService.getContentList();
    if (!mounted) return;
    setState(() {
      _books = resp.success && resp.data is List<ContentItem>
          ? (resp.data as List<ContentItem>)
              .where((b) => b.audiobookId != null && b.status != 'processing')
              .toList()
          : const [];
      _loading = false;
    });
  }

  Future<void> _share() async {
    final book = _selected;
    if (book?.audiobookId == null) {
      AppSnackbar.warning('Pick a story to share', context: context);
      return;
    }
    setState(() => _sharing = true);
    final resp = await DatabaseService.sharePost(
      audiobookId: book!.audiobookId!,
      caption: _captionCtrl.text.trim().isEmpty ? null : _captionCtrl.text.trim(),
      includeMusic: _includeMusic,
    );
    if (!mounted) return;
    setState(() => _sharing = false);
    if (resp.success) {
      AppSnackbar.success('Shared to the hub', context: context);
      Navigator.of(context).pop();
    } else {
      AppSnackbar.error(resp.message, context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  BackPill(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 12),
                  const Text('Share a story',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _books.isEmpty
                      ? const Center(
                          child: Text('You have no finished stories to share yet.',
                              style: TextStyle(color: AppColors.textSecondary)))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          children: [
                            const Text('Choose a story',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 8),
                            ..._books.map(_bookTile),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _captionCtrl,
                              minLines: 2,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                hintText: 'Say something about this story (optional)',
                              ),
                            ),
                            const SizedBox(height: 12),
                            _MusicNotice(
                              value: _includeMusic,
                              onChanged: (v) => setState(() => _includeMusic = v),
                            ),
                          ],
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _sharing ? null : _share,
                  child: _sharing
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Share',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bookTile(ContentItem book) {
    final selected = _selected?.audiobookId == book.audiobookId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        color: selected ? AppColors.iconCircleBlue : null,
        padding: const EdgeInsets.all(10),
        onTap: () => setState(() => _selected = book),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 48,
                height: 48,
                child: (book.coverImage != null && book.coverImage!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: book.coverImage!,
                        fit: BoxFit.cover,
                        memCacheWidth: 140,
                        errorWidget: (_, _, _) => _fallback(),
                      )
                    : _fallback(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.primaryBlueDark),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => Container(
        color: AppColors.softLavender,
        child: const Icon(Icons.auto_stories_rounded,
            color: AppColors.primaryBlueDark),
      );
}

/* The background-music choice. Off by default and clearly explained, since
   copyrighted music shouldn't be redistributed even in a private hub. */
class _MusicNotice extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _MusicNotice({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: AppColors.softPeach.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include background music',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text(
              'Off by default. Only turn this on if the music is royalty-free — '
              'shared stories otherwise include just the story, pictures, and voice.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            activeThumbColor: AppColors.primaryBlueDark,
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
