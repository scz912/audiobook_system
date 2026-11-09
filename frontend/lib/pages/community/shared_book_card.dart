import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../models/community/shared_book.dart';
import '../../theme/app_colors.dart';
import '../child/audio_player_page.dart';

/* Save a shared book into my library, or show that it's already there.
   [onSave] returns whether it worked; the button shows a spinner meanwhile. */
class SaveToLibraryButton extends StatefulWidget {
  final bool inMyLibrary;
  final Future<bool> Function() onSave;
  final bool compact;
  const SaveToLibraryButton({
    super.key,
    required this.inMyLibrary,
    required this.onSave,
    this.compact = false,
  });

  @override
  State<SaveToLibraryButton> createState() => _SaveToLibraryButtonState();
}

class _SaveToLibraryButtonState extends State<SaveToLibraryButton> {
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.onSave();
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inMyLibrary) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 18, color: AppColors.success),
          const SizedBox(width: 6),
          Text(context.tr('community.in_library'),
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  fontSize: 13)),
        ],
      );
    }
    return OutlinedButton.icon(
      onPressed: _saving ? null : _save,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.primaryBlueDark),
        visualDensity: widget.compact ? VisualDensity.compact : null,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: _saving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.download_rounded, size: 18),
      label: Text(context.tr('community.save_to_library'),
          style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

// A book shared in a chat: cover, title, a Listen button and save-to-library.
class SharedBookCard extends StatelessWidget {
  final SharedBook book;
  final Future<bool> Function() onSave;
  const SharedBookCard({super.key, required this.book, required this.onSave});

  void _listen(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AudioPlayerPage(
        title: book.title,
        audiobookId: book.audiobookId,
        previewMode: true,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _listen(context),
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: (book.coverImage ?? '').isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: book.coverImage!,
                            fit: BoxFit.cover,
                            memCacheWidth: 160,
                            errorWidget: (_, _, _) => const _CoverFallback(),
                          )
                        : const _CoverFallback(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(
                        context.tr(book.isInteractive
                            ? 'community.book_interactive'
                            : 'community.book_linear'),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.play_circle_fill_rounded,
                    color: AppColors.primaryBlueDark, size: 30),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SaveToLibraryButton(
            inMyLibrary: book.inMyLibrary,
            onSave: onSave,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.softLavender,
      child: const Icon(Icons.auto_stories_rounded,
          color: AppColors.primaryBlueDark),
    );
  }
}
