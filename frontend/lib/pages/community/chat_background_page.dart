import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../i18n/i18n.dart';
import '../../models/community/contact_settings.dart';
import '../../services/database_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/chat_background.dart';

/* Pick the background of the chat with one contact. Laid out like a
   keyboard theme picker: sections of preview tiles (my picture, default,
   colours, light and dark gradients); tapping one shows a full preview
   with an Apply button. Pops with the saved ContactSettings. */
class ChatBackgroundPage extends StatefulWidget {
  final String contactId;
  final String contactName;
  final ChatBackground current;
  const ChatBackgroundPage({
    super.key,
    required this.contactId,
    required this.contactName,
    required this.current,
  });

  @override
  State<ChatBackgroundPage> createState() => _ChatBackgroundPageState();
}

class _ChatBackgroundPageState extends State<ChatBackgroundPage> {
  late ChatBackground _current = widget.current;
  ContactSettings? _saved;
  final _picker = ImagePicker();

  static const _darkGradients = {'dusk', 'night'};

  Future<void> _uploadPicture() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null || !mounted) return;
    // Preview the file from the phone; it's uploaded only on Apply.
    await _preview(ChatBackground.image(file.path), localPath: file.path);
  }

  Future<void> _preview(ChatBackground bg, {String? localPath}) async {
    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => _PreviewSheet(background: bg),
    );
    if (apply != true || !mounted) return;

    final resp = localPath != null
        ? await DatabaseService.uploadChatBackground(widget.contactId, localPath)
        : await DatabaseService.updateContactSettings(widget.contactId, {
            'background_type': bg.isNone ? 'none' : bg.type,
            if (!bg.isNone) 'background_value': bg.value,
          });
    if (!mounted) return;
    if (resp.success && resp.data is ContactSettings) {
      final saved = resp.data as ContactSettings;
      setState(() {
        _saved = saved;
        _current = saved.background;
      });
      AppSnackbar.success(context.trRead('contacts.background_applied'),
          context: context);
    } else {
      AppSnackbar.error(resp.message, context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final light = chatBackgroundGradients.keys
        .where((k) => !_darkGradients.contains(k))
        .toList();
    return PopScope(
      canPop: false,
      // Hand back what was saved so the chat and profile update.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_saved);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      BackPill(onTap: () => Navigator.of(context).pop(_saved)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.tr('contacts.chat_background'),
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w700)),
                            Text(
                              context
                                  .tr('contacts.background_for')
                                  .replaceAll('{name}', widget.contactName),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _section(context.tr('contacts.my_picture'), [
                _UploadTile(onTap: _uploadPicture),
                if (_current.type == 'image')
                  _tile(_current, onTap: () => _preview(_current)),
              ]),
              _section(context.tr('contacts.default'), [
                _tile(const ChatBackground.none()),
              ]),
              _section(context.tr('contacts.colors'), [
                for (final hex in chatBackgroundColors)
                  _tile(ChatBackground.color(hex)),
              ]),
              _section(context.tr('contacts.light_gradients'), [
                for (final name in light) _tile(ChatBackground.gradient(name)),
              ]),
              _section(context.tr('contacts.dark_gradients'), [
                for (final name in _darkGradients)
                  _tile(ChatBackground.gradient(name)),
              ]),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(ChatBackground bg, {VoidCallback? onTap}) => _BackgroundTile(
        background: bg,
        selected: bg == _current,
        onTap: onTap ?? () => _preview(bg),
      );

  // A heading and a three-across grid of tiles.
  Widget _section(String title, List<Widget> tiles) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      sliver: SliverList.list(children: [
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                fontSize: 14)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
          children: tiles,
        ),
      ]),
    );
  }
}

/* One choice: a tiny chat drawn on the background, with a check badge
   when it's the one in use. */
class _BackgroundTile extends StatelessWidget {
  final ChatBackground background;
  final bool selected;
  final VoidCallback onTap;
  const _BackgroundTile({
    required this.background,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: _label(context),
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? AppColors.primaryBlueDark : AppColors.cardBorder,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: ChatBackgroundView(
                  background: background,
                  borderRadius: BorderRadius.circular(selected ? 11 : 13),
                  child: const _MiniChat(scale: 0.55),
                ),
              ),
            ),
            if (selected)
              const Positioned(
                top: 6,
                right: 6,
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: AppColors.primaryBlueDark,
                  child: Icon(Icons.check_rounded, size: 15, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _label(BuildContext context) {
    switch (background.type) {
      case 'color':
        return '${context.tr('contacts.colors')} ${background.value}';
      case 'gradient':
        return '${context.tr('contacts.gradient')} ${background.value}';
      case 'image':
        return context.tr('contacts.my_picture');
      default:
        return context.tr('contacts.default');
    }
  }
}

class _UploadTile extends StatelessWidget {
  final VoidCallback onTap;
  const _UploadTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.tr('contacts.upload_picture'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_photo_alternate_outlined,
                  size: 32, color: AppColors.primaryBlueDark),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(context.tr('contacts.upload_picture'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* A pretend conversation used to preview a background: one bubble from
   them, one from me. [scale] shrinks it to fit a tile. */
class _MiniChat extends StatelessWidget {
  final double scale;
  const _MiniChat({this.scale = 1});

  @override
  Widget build(BuildContext context) {
    Widget bubble(String text, bool mine) => Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: EdgeInsets.symmetric(vertical: 4 * scale),
            padding: EdgeInsets.symmetric(
                horizontal: 12 * scale, vertical: 8 * scale),
            constraints: BoxConstraints(maxWidth: 220 * scale + 40),
            decoration: BoxDecoration(
              color: mine ? AppColors.primaryBlue : AppColors.surface,
              borderRadius: BorderRadius.circular(14 * scale),
            ),
            child: Text(text,
                style: TextStyle(
                    fontSize: 14 * scale,
                    color: AppColors.textPrimary,
                    height: 1.25)),
          ),
        );
    return Padding(
      padding: EdgeInsets.all(10 * scale),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          bubble(scale < 1 ? 'Hi!' : context.tr('contacts.preview_them'), false),
          bubble(scale < 1 ? 'Hello' : context.tr('contacts.preview_me'), true),
          if (scale >= 1)
            bubble(context.tr('contacts.preview_them_2'), false),
        ],
      ),
    );
  }
}

// The full preview with Apply, like a keyboard theme preview.
class _PreviewSheet extends StatelessWidget {
  final ChatBackground background;
  const _PreviewSheet({required this.background});

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('contacts.preview'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SizedBox(
              height: height * 0.42,
              child: ChatBackgroundView(
                background: background,
                borderRadius: BorderRadius.circular(18),
                child: const _MiniChat(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: AppColors.textPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(context.tr('common.cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: AppColors.primaryBlueDark,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(context.tr('contacts.apply'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
