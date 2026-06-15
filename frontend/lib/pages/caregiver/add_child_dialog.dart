import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/child_profile.dart';
import '../../state/profiles_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';

class _AvatarOption {
  final String emoji;
  final Color color;
  const _AvatarOption(this.emoji, this.color);
}

class AddChildDialog extends StatefulWidget {
  /* Set this to edit a child: the form pre-fills and Save updates instead
     of adding. Leave null to add a new child. */
  final ChildProfile? existing;

  const AddChildDialog({super.key, this.existing});

  @override
  State<AddChildDialog> createState() => _AddChildDialogState();
}

class _AddChildDialogState extends State<AddChildDialog> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  late String _emoji;
  late Color _color;
  bool _saving = false;

  final List<_AvatarOption> _avatars = const [
    _AvatarOption('🌟', AppColors.softYellow),
    _AvatarOption('🌸', AppColors.softPink),
    _AvatarOption('🦁', AppColors.softPeach),
    _AvatarOption('🌈', AppColors.softLavender),
    _AvatarOption('🐢', AppColors.softMint),
    _AvatarOption('🚀', AppColors.iconCircleBlue),
  ];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _ageCtrl.text = e.age.toString();
      _emoji = e.avatarEmoji;
      _color = e.avatarColor;
    } else {
      _emoji = '🌟';
      _color = AppColors.softPink;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final age = int.tryParse(_ageCtrl.text.trim()) ?? 0;
    if (name.isEmpty || age <= 0) return;
    setState(() => _saving = true);
    final profiles = context.read<ProfilesState>();
    final ok = _isEdit
        ? await profiles.updateProfile(
            widget.existing!.childId,
            name: name,
            age: age,
            avatarEmoji: _emoji,
            avatarColorHex: ChildProfile.colorToHex(_color),
          )
        : await profiles.addProfile(
            name: name,
            age: age,
            avatarEmoji: _emoji,
            avatarColorHex: ChildProfile.colorToHex(_color),
            favoriteGenre: 'Fantasy',
          );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      AppSnackbar.error(context.trRead('add_child.save_error'),
          context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                    _isEdit ? 'add_child.edit_title' : 'add_child.title'),
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                    hintText: context.tr('add_child.name')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ageCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    hintText: context.tr('add_child.age')),
              ),
              const SizedBox(height: 16),
              Text(context.tr('add_child.avatar'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _avatars.map((a) {
                  final selected = a.emoji == _emoji;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _emoji = a.emoji;
                      _color = a.color;
                    }),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: a.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? AppColors.primaryBlueDark
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(a.emoji, style: const TextStyle(fontSize: 24)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.tr('common.cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(context.tr('common.save'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
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
