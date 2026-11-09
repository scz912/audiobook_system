import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';

/* A smiley button for a text box. Tapping it opens a sheet of emoji
   grouped by theme; picking one types it at the cursor (or replaces the
   selected text). The sheet stays open so several can be added in a row. */
class EmojiPickerButton extends StatelessWidget {
  final TextEditingController controller;
  const EmojiPickerButton({super.key, required this.controller});

  static const _groups = <(String, IconData, List<String>)>[
    ('emoji.smileys', Icons.emoji_emotions_outlined, [
      '😀', '😃', '😄', '😁', '😊', '🙂', '😉', '😍', '🥰', '😘',
      '😋', '😎', '🤗', '🤩', '🥳', '😌', '😴', '🤔', '😮', '😅',
      '😂', '🤣', '😢', '😭', '😟', '😕', '😬', '🙃', '😇', '🤭',
    ]),
    ('emoji.hearts', Icons.favorite_border_rounded, [
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🤍', '💖', '💕', '💞',
      '👍', '👏', '🙌', '🙏', '👋', '🤝', '💪', '✌️', '👌', '🤞',
      '⭐', '🌟', '✨', '🎉', '🎊', '🏆', '🥇', '💯', '✅', '🎈',
    ]),
    ('emoji.animals', Icons.pets_rounded, [
      '🐶', '🐱', '🐭', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁',
      '🐮', '🐷', '🐸', '🐵', '🐔', '🐧', '🐦', '🐤', '🦄', '🐝',
      '🦋', '🐢', '🐠', '🐬', '🐳', '🦕', '🌸', '🌻', '🌈', '🌳',
    ]),
    ('emoji.food', Icons.restaurant_rounded, [
      '🍎', '🍌', '🍇', '🍓', '🍉', '🍊', '🍍', '🥭', '🍒', '🥝',
      '🥕', '🌽', '🍞', '🧀', '🍕', '🍔', '🍟', '🍪', '🍰', '🧁',
      '🍩', '🍦', '🍫', '🍬', '🥛', '🧃', '🍵', '🍚', '🍜', '🍳',
    ]),
    ('emoji.activities', Icons.sports_soccer_rounded, [
      '📚', '📖', '🎧', '🎵', '🎶', '🎹', '🎨', '🖍️', '✏️', '🧩',
      '⚽', '🏀', '🏸', '🚲', '🛝', '🏊', '🎮', '🧸', '🪁', '🚀',
      '🏠', '🏫', '🌙', '☀️', '⛅', '🌧️', '❄️', '🎂', '🎁', '💤',
    ]),
  ];

  void _insert(String emoji) {
    final value = controller.value;
    final text = value.text;
    final sel = value.selection;
    // No cursor yet (box never focused): add to the end.
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  Future<void> _open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheetContext) => DefaultTabController(
        length: _groups.length,
        child: SizedBox(
          height: 300,
          child: Column(
            children: [
              TabBar(
                labelColor: AppColors.primaryBlueDark,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primaryBlueDark,
                tabs: [
                  // The tooltip names each group for screen readers.
                  for (final g in _groups)
                    Tab(
                      icon: Tooltip(
                        message: sheetContext.tr(g.$1),
                        child: Icon(g.$2),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final g in _groups)
                      GridView.count(
                        crossAxisCount: 8,
                        padding: const EdgeInsets.all(8),
                        children: [
                          for (final e in g.$3)
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _insert(e),
                              child: Center(
                                child: Text(e, style: const TextStyle(fontSize: 26)),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.tr('emoji.add'),
      onPressed: () => _open(context),
      icon: const Icon(Icons.emoji_emotions_outlined,
          color: AppColors.textSecondary),
    );
  }
}
