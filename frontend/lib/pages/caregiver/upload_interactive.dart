part of 'upload_content_page.dart';

/* Interactive audiobook pieces for the upload screen.

   How an interactive book is laid out:
   - A question ("interaction") page has 2-4 choices the child taps.
   - The page right after it is its response page. It can't be a question.
     - Normal: one page for everyone, with {choice} where the child's
       answer is read out.
     - Split: two different pages (same page number), one per choice, so a
       split question has exactly 2 choices. The story joins back after. */

// The response page, or one version of a split page.
class _ResponseDraft {
  final TextEditingController text = TextEditingController();
  String? imagePath;
  void dispose() => text.dispose();
}

// One page in the interactive builder, plus its response page(s) if it asks a question.
class _InteractivePageDraft {
  static const minChoices = 2;
  static const maxChoices = 4;

  final TextEditingController text = TextEditingController();
  String? imagePath;
  bool interactive = false;
  bool split = false;
  final List<TextEditingController> choices = [
    TextEditingController(),
    TextEditingController(),
  ];
  final _ResponseDraft response = _ResponseDraft();
  final List<_ResponseDraft> branches = [_ResponseDraft(), _ResponseDraft()];

  // Filled-in choices, trimmed.
  List<String> get choiceTexts => choices
      .map((c) => c.text.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  bool get canAddChoice => !split && choices.length < maxChoices;

  void addChoice() {
    if (canAddChoice) choices.add(TextEditingController());
  }

  void removeChoice(int index) {
    if (choices.length <= minChoices) return;
    _disposeLater(choices.removeAt(index));
  }

  // A split question only has 2 choices (one per page version).
  void setSplit(bool value) {
    split = value;
    if (value) {
      while (choices.length > 2) {
        _disposeLater(choices.removeLast());
      }
    }
  }

  void dispose() {
    text.dispose();
    for (final c in choices) {
      c.dispose();
    }
    response.dispose();
    for (final b in branches) {
      b.dispose();
    }
  }

  // The removed field is still on screen this frame, so wait a frame.
  static void _disposeLater(TextEditingController c) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
}

/* Put the {choice} token into [controller] at [offset], adding spaces so it
   doesn't stick to the words around it. */
void _insertChoiceToken(TextEditingController controller, int offset) {
  const token = AudiobookPage.choiceToken;
  final text = controller.text;
  final at = offset < 0 ? text.length : offset.clamp(0, text.length);
  final before = text.substring(0, at);
  final after = text.substring(at);
  final lead = before.isEmpty || before.endsWith(' ') ? '' : ' ';
  final trail =
      after.isEmpty || after.startsWith(' ') || RegExp(r'^[.,!?;:]').hasMatch(after)
          ? ''
          : ' ';
  final inserted = '$lead$token$trail';
  controller.value = TextEditingValue(
    text: before + inserted + after,
    selection: TextSelection.collapsed(offset: before.length + inserted.length),
  );
}

/* The Linear / Interactive slider at the top of the upload screen. */
class _FormatSlider extends StatelessWidget {
  final _BookFormat format;
  final ValueChanged<_BookFormat> onChanged;

  const _FormatSlider({required this.format, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final interactive = format == _BookFormat.interactive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.softLavender.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Stack(
            children: [
              // The sliding thumb.
              AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment:
                    interactive ? Alignment.centerRight : Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  _segment('Linear', Icons.menu_book_rounded,
                      _BookFormat.linear),
                  _segment('Interactive', Icons.touch_app_rounded,
                      _BookFormat.interactive),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            interactive
                ? 'The story pauses and lets the child choose what happens.'
                : 'A classic story, read from start to end.',
            key: ValueKey(interactive),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _segment(String label, IconData icon, _BookFormat value) {
    final selected = format == value;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(value),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: selected
                    ? AppColors.primaryBlueDark
                    : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color:
                    selected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// "How interactive books work" button at the top of the interactive Write form.
class _GuideBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _GuideBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.softYellow.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded,
                  color: AppColors.textPrimary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'New to interactive books? Read the guide',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

/* One page in the interactive Write form. Turning on "Interactive" makes it
   a question page with choices and a response box for the next page. */
class _InteractivePageCard extends StatelessWidget {
  final _InteractivePageDraft draft;
  final int pageNumber;
  final bool canRemove;
  final VoidCallback onChanged;
  final Future<void> Function(void Function(String path)) pickImage;
  final VoidCallback onRemove;

  const _InteractivePageCard({
    super.key,
    required this.draft,
    required this.pageNumber,
    required this.canRemove,
    required this.onChanged,
    required this.pickImage,
    required this.onRemove,
  });

  void _update(VoidCallback change) {
    change();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final d = draft;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: d.interactive
                      ? AppColors.softLavender
                      : AppColors.softMint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  d.interactive ? 'Page $pageNumber · Question' : 'Page $pageNumber',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              const Spacer(),
              _InteractiveChip(
                selected: d.interactive,
                onTap: () => _update(() => d.interactive = !d.interactive),
              ),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.textSecondary),
                  tooltip: 'Remove page',
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: d.text,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: d.interactive
                  ? 'Story text that ends with a question, e.g. '
                      '"What should Mia pack for the picnic?"'
                  : 'Text for this page…',
            ),
          ),
          if (d.interactive) ...[
            const SizedBox(height: 12),
            Text(
              d.split
                  ? 'Choices (2 - one for each page version)'
                  : 'Choices the child can tap (2 to 4)',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < d.choices.length; i++)
              Padding(
                key: ObjectKey(d.choices[i]),
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: d.choices[i],
                        maxLength: 60,
                        onChanged: (_) => onChanged(),
                        decoration: InputDecoration(
                          hintText: 'Choice ${i + 1}, e.g. a red apple',
                          isDense: true,
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    if (d.choices.length > _InteractivePageDraft.minChoices)
                      IconButton(
                        onPressed: () => _update(() => d.removeChoice(i)),
                        icon: const Icon(Icons.remove_circle_outline_rounded,
                            color: AppColors.textSecondary),
                        tooltip: 'Remove choice',
                      ),
                  ],
                ),
              ),
            if (d.canAddChoice)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _update(d.addChoice),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryBlueDark),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add choice',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
          ],
          const SizedBox(height: 10),
          _ImagePickerBox(
            imagePath: d.imagePath,
            height: 130,
            hint: 'Add a picture for this page',
            onPick: () => pickImage((p) => d.imagePath = p),
            onClear: d.imagePath == null
                ? null
                : () => _update(() => d.imagePath = null),
          ),
          if (d.interactive) ...[
            const SizedBox(height: 14),
            _ResponseBox(
              draft: d,
              pageNumber: pageNumber + 1,
              onChanged: onChanged,
              pickImage: pickImage,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: _SplitToggle(
                value: d.split,
                onChanged: (v) => _update(() => d.setSplit(v)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// "Interactive" on/off pill at the top right of a page card.
class _InteractiveChip extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  const _InteractiveChip({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBlueDark : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primaryBlueDark : AppColors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_rounded : Icons.touch_app_outlined,
              size: 15,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              'Interactive',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// "Split into 2 pages" switch at the bottom right of a question card.
class _SplitToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SplitToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Split into 2 pages',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text('A different next page for each choice',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
        const SizedBox(width: 6),
        Switch.adaptive(
          value: value,
          activeThumbColor: AppColors.primaryBlueDark,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/* The box for the page after a question: one page with the child's-answer
   placeholder, or (split) two pages, one per choice. */
class _ResponseBox extends StatelessWidget {
  final _InteractivePageDraft draft;
  final int pageNumber;
  final VoidCallback onChanged;
  final Future<void> Function(void Function(String path)) pickImage;

  const _ResponseBox({
    required this.draft,
    required this.pageNumber,
    required this.onChanged,
    required this.pickImage,
  });

  @override
  Widget build(BuildContext context) {
    final d = draft;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.softLavender.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label on the top left.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Text(
              d.split
                  ? 'Page $pageNumber · Split pages'
                  : 'Page $pageNumber · Response page',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            d.split
                ? 'Write a different page for each choice. Only the one the '
                    'child picks is read, then the story carries on as normal.'
                : 'Everyone hears this page. Put the placeholder where the '
                    'child\'s answer should be read out.',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (!d.split) ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                _PlaceholderChip(
                  onTap: () {
                    final c = d.response.text;
                    _insertChoiceToken(c, c.selection.baseOffset);
                  },
                ),
                const Text('Drag into the text, or tap to add at the cursor',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 11.5)),
              ],
            ),
            const SizedBox(height: 8),
            _PlaceholderTextField(controller: d.response.text),
            const SizedBox(height: 8),
            _ImagePickerBox(
              imagePath: d.response.imagePath,
              height: 110,
              hint: 'Add a picture for this page',
              onPick: () => pickImage((p) => d.response.imagePath = p),
              onClear: d.response.imagePath == null
                  ? null
                  : () {
                      d.response.imagePath = null;
                      onChanged();
                    },
            ),
          ] else
            for (var b = 0; b < 2; b++) ...[
              _BranchBox(
                label: _branchLabel(b),
                branch: d.branches[b],
                onChanged: onChanged,
                pickImage: pickImage,
              ),
              if (b == 0) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  String _branchLabel(int b) {
    final choice = draft.choices.length > b ? draft.choices[b].text.trim() : '';
    return choice.isEmpty ? 'If choice ${b + 1} is picked' : 'If "$choice" is picked';
  }
}

// One version of a split page, labelled with the choice that leads to it.
class _BranchBox extends StatelessWidget {
  final String label;
  final _ResponseDraft branch;
  final VoidCallback onChanged;
  final Future<void> Function(void Function(String path)) pickImage;

  const _BranchBox({
    required this.label,
    required this.branch,
    required this.onChanged,
    required this.pickImage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Label on the top right.
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.iconCircleBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppColors.primaryBlueDark),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: branch.text,
            maxLines: 3,
            decoration:
                const InputDecoration(hintText: 'Text for this version…'),
          ),
          const SizedBox(height: 8),
          _ImagePickerBox(
            imagePath: branch.imagePath,
            height: 100,
            hint: 'Add a picture',
            onPick: () => pickImage((p) => branch.imagePath = p),
            onClear: branch.imagePath == null
                ? null
                : () {
                    branch.imagePath = null;
                    onChanged();
                  },
          ),
        ],
      ),
    );
  }
}

// The draggable "Child's answer" label. Dropped or tapped, it adds {choice}.
class _PlaceholderChip extends StatelessWidget {
  final VoidCallback onTap;
  const _PlaceholderChip({required this.onTap});

  static Widget _chip({double opacity = 1}) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primaryBlueDark,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drag_indicator_rounded, size: 16, color: Colors.white),
            SizedBox(width: 4),
            Text(
              'Child\'s answer',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Draggable<String>(
      data: AudiobookPage.choiceToken,
      // The drop point is the finger, so the text lands where it's released.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(color: Colors.transparent, child: _chip()),
      childWhenDragging: _chip(opacity: 0.4),
      child: GestureDetector(onTap: onTap, child: _chip()),
    );
  }
}

/* Response text field that accepts the dragged placeholder and inserts it
   at the spot in the text where it was dropped. */
class _PlaceholderTextField extends StatelessWidget {
  final TextEditingController controller;
  const _PlaceholderTextField({required this.controller});

  // The text layout inside the TextField, used to turn a drop point into a text position.
  static RenderEditable? _findEditable(RenderObject? node) {
    if (node == null) return null;
    if (node is RenderEditable) return node;
    RenderEditable? found;
    node.visitChildren((child) => found ??= _findEditable(child));
    return found;
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          details.data == AudiobookPage.choiceToken,
      onAcceptWithDetails: (details) {
        final editable = _findEditable(context.findRenderObject());
        final offset = editable != null
            ? editable.getPositionForPoint(details.offset).offset
            : controller.text.length;
        _insertChoiceToken(controller, offset);
      },
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: hovering
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlueDark.withValues(alpha: 0.35),
                      blurRadius: 0,
                      spreadRadius: 2,
                    ),
                  ]
                : const [],
          ),
          child: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'e.g. Mia put {choice} in her basket. It looked yummy!',
            ),
          ),
        );
      },
    );
  }
}

/* AI settings for interactive books: how many question pages, and how many
   of them split the next page. */
class _InteractionSettingsCard extends StatelessWidget {
  final int pageCount;
  final int interactions;
  final int splits;
  final ValueChanged<int> onInteractionsChanged;
  final ValueChanged<int> onSplitsChanged;
  final VoidCallback onShowGuide;

  const _InteractionSettingsCard({
    required this.pageCount,
    required this.interactions,
    required this.splits,
    required this.onInteractionsChanged,
    required this.onSplitsChanged,
    required this.onShowGuide,
  });

  String _plural(int n, String word) => n == 1 ? '$n $word' : '$n ${word}s';

  @override
  Widget build(BuildContext context) {
    // 1 interaction per 4 pages, rounded down (7 pages -> 1).
    final cap = pageCount ~/ 4;
    final placeholders = interactions - splits;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppColors.iconCirclePurple,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.touch_app_rounded,
                    size: 18, color: AppColors.primaryBlueDark),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Interactions',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                onPressed: onShowGuide,
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryBlueDark),
                icon: const Icon(Icons.help_outline_rounded, size: 18),
                label: const Text('Guide'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _Label('Interaction frequency'),
          _CountStepper(
            title: 'Interaction frequency',
            value: interactions,
            min: 1,
            max: cap,
            onChanged: onInteractionsChanged,
          ),
          const SizedBox(height: 6),
          Text(
            'Up to 1 interaction for every 4 pages, rounded down. With '
            '$pageCount pages you can have up to ${_plural(cap, 'interaction')}. '
            'Fewer pauses keep the story calm and easy to follow.',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          const _Label('Interaction split'),
          _CountStepper(
            title: 'Interaction split',
            value: splits,
            min: 0,
            max: interactions,
            onChanged: onSplitsChanged,
          ),
          const SizedBox(height: 6),
          Text(
            splits == 0
                ? 'No split pages. After each question the next page is the '
                    'same for everyone and simply says the child\'s answer '
                    '(2 or 3 choices per question).'
                : '${_plural(splits, 'question')} will split: the page right '
                    'after it gets 2 different versions, one for each of its 2 '
                    'choices, then the story joins back together.'
                    '${placeholders > 0 ? ' The other ${_plural(placeholders, 'question')} '
                        'will say the child\'s answer on the next page '
                        '(2 or 3 choices).' : ''}',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/* A number box with minus on the left and plus on the right. Tapping the
   number opens a number pad; values above [max] snap back to [max]. */
class _CountStepper extends StatelessWidget {
  final String title;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _CountStepper({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  Future<void> _typeValue(BuildContext context) async {
    final typed = await showDialog<int>(
      context: context,
      builder: (_) => _NumberEntryDialog(title: title, initial: value, max: max),
    );
    if (typed == null) return;
    if (typed > max && context.mounted) {
      AppSnackbar.info('The most allowed is $max, so it was set to $max.',
          context: context);
    }
    onChanged(typed.clamp(min, max));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepButton(
          icon: Icons.remove_rounded,
          onTap: value > min ? () => onChanged(value - 1) : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Material(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _typeValue(context),
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Text(
                  '$value',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _StepButton(
          icon: Icons.add_rounded,
          onTap: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.primaryBlueDark,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.cardBorder,
        minimumSize: const Size(48, 48),
      ),
      icon: Icon(icon),
    );
  }
}

// Number-pad dialog for _CountStepper. Returns the typed number or null.
class _NumberEntryDialog extends StatefulWidget {
  final String title;
  final int initial;
  final int max;
  const _NumberEntryDialog(
      {required this.title, required this.initial, required this.max});

  @override
  State<_NumberEntryDialog> createState() => _NumberEntryDialogState();
}

class _NumberEntryDialogState extends State<_NumberEntryDialog> {
  late final _ctrl = TextEditingController(text: '${widget.initial}')
    ..selection = TextSelection(baseOffset: 0, extentOffset: '${widget.initial}'.length);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _done() => Navigator.of(context).pop(int.tryParse(_ctrl.text.trim()));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        decoration: InputDecoration(helperText: 'Maximum ${widget.max}'),
        onSubmitted: (_) => _done(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlueDark),
          onPressed: _done,
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/* Explains interactive books: how they play, what each option does, and
   tips for writing good ones. */
class _InteractiveGuideDialog extends StatelessWidget {
  const _InteractiveGuideDialog();

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const _InteractiveGuideDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Icon(Icons.touch_app_rounded,
                    color: AppColors.primaryBlueDark),
                SizedBox(width: 10),
                Expanded(
                  child: Text('How interactive audiobooks work',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'An interactive audiobook pauses at certain pages and asks '
                    'the child a question. The story waits until the child taps '
                    'one of the choices, then answers back using what they '
                    'picked. The child becomes part of the story.',
                    style: TextStyle(height: 1.45),
                  ),
                  _GuideSection(
                    icon: Icons.touch_app_outlined,
                    title: 'Interactive (top right of a page)',
                    body: 'Turns that page into a question page. Write the story '
                        'text so it ends with a clear question. The page right '
                        'after it becomes its response page, so it can\'t be a '
                        'question too. That\'s why a question page uses up 2 '
                        'page numbers.',
                  ),
                  _GuideSection(
                    icon: Icons.list_rounded,
                    title: 'Choices',
                    body: 'The buttons the child taps. Start with 2 and add up to '
                        '4. Each choice is also read aloud, so keep it short, '
                        'like "a red apple" or "go to the beach".',
                  ),
                  _GuideSection(
                    icon: Icons.short_text_rounded,
                    title: 'Response page and the "Child\'s answer" placeholder',
                    body: 'Everyone hears the same response page, but the '
                        'placeholder is replaced with the child\'s choice. Drag '
                        'the "Child\'s answer" label into the text (or tap it to '
                        'add it at the cursor). It shows as {choice}. Example: '
                        '"Mia put {choice} in her basket." becomes "Mia put a '
                        'red apple in her basket."',
                  ),
                  _GuideSection(
                    icon: Icons.call_split_rounded,
                    title: 'Split into 2 pages (bottom right)',
                    body: 'Instead of one response page, you write 2 different '
                        'pages: one for each choice. Only the page for the '
                        'child\'s choice is read. Split questions have exactly '
                        '2 choices, so extra choices are removed. After the '
                        'split, the story joins back into one page for everyone.',
                  ),
                  _GuideSection(
                    icon: Icons.image_outlined,
                    title: 'Pictures',
                    body: 'Every page, response page, and split version can have '
                        'its own picture, so a split can show 2 different scenes.',
                  ),
                  SizedBox(height: 14),
                  Text('Suggestions',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  _GuideTip('Use about 1 question for every 4 pages. Too many '
                      'pauses can be tiring.'),
                  _GuideTip('Make every choice a good one. There should be no '
                      'right or wrong answer, and nothing scary on any path.'),
                  _GuideTip('Keep choices short, concrete and easy to picture, '
                      'and make them clearly different from each other.'),
                  _GuideTip('Read the response page out loud with each choice '
                      'in place of {choice} to check it always makes sense.'),
                  _GuideTip('Save split pages for bigger moments, and write the '
                      'page after a split so it fits both versions.'),
                  _GuideTip('Give a gentle cue before the question, like '
                      '"Now it\'s your turn to choose!", so the pause feels '
                      'expected rather than sudden.'),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlueDark,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _GuideSection(
      {required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: AppColors.iconCircleBlue,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: AppColors.primaryBlueDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body,
                    style: const TextStyle(
                        color: AppColors.textSecondary, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideTip extends StatelessWidget {
  final String text;
  const _GuideTip(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.check_circle_outline_rounded,
                size: 16, color: AppColors.success),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textSecondary, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
