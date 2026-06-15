import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/app_strings.dart';
import '../../i18n/i18n.dart';
import '../../models/child_profile.dart';
import '../../models/user_settings.dart';
import '../../state/language_state.dart';
import '../../state/profiles_state.dart';
import '../../state/settings_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/soft_card.dart';

class SettingsPage extends StatefulWidget {
  /* Called when the header back arrow is tapped. The shell uses it to go
     back to the Dashboard tab, since pop() doesn't work for a tab body. */
  final VoidCallback? onBack;
  const SettingsPage({super.key, this.onBack});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // The child we asked SettingsState to load (stops us asking twice).
  String? _pendingLoad;

  @override
  Widget build(BuildContext context) {
    final profiles = context.watch<ProfilesState>().profiles;
    final settings = context.watch<SettingsState>();

    // Use the current child if it still exists, else the first one.
    String? activeChildId = settings.childId;
    final validCurrent =
        activeChildId != null && profiles.any((p) => p.childId == activeChildId);
    if (!validCurrent && profiles.isNotEmpty) {
      activeChildId = profiles.first.childId;
      _loadChild(activeChildId);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        BackPill(onTap: widget.onBack ?? () => Navigator.of(context).maybePop()),
        const SizedBox(height: 16),
        Text(
          context.tr('settings.title'),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('settings.subtitle'),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 18),
        if (profiles.isEmpty)
          const _NoChildrenCard()
        else ...[
          _ChildSelector(
            profiles: profiles,
            selectedId: activeChildId,
            onSelect: (id) => _loadChild(id, force: true),
          ),
          const SizedBox(height: 14),
          if (settings.loading)
            const SoftCard(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else ...[
            const _NarrationCard(),
            const SizedBox(height: 14),
            const _SensoryCard(),
            const SizedBox(height: 14),
            const _TextSizeCard(),
          ],
          const SizedBox(height: 14),
        ],
        const _LanguageCard(),
        const SizedBox(height: 14),
        const _PinChangeCard(),
      ],
    );
  }

  void _loadChild(String childId, {bool force = false}) {
    if (!force && _pendingLoad == childId) return;
    _pendingLoad = childId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SettingsState>().loadForChild(childId);
    });
  }
}

// Row of the caregiver's children — pick whose settings to edit.
class _ChildSelector extends StatelessWidget {
  final List<ChildProfile> profiles;
  final String? selectedId;
  final void Function(String childId) onSelect;
  const _ChildSelector({
    required this.profiles,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('settings.configuring_for'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: profiles.map((p) {
              final selected = p.childId == selectedId;
              return InkWell(
                onTap: () => onSelect(p.childId),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primaryBlue : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? AppColors.primaryBlueDark
                          : AppColors.cardBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: p.avatarColor,
                        child: Text(p.avatarEmoji,
                            style: const TextStyle(fontSize: 14)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        p.name,
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _NoChildrenCard extends StatelessWidget {
  const _NoChildrenCard();
  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppColors.primaryBlueDark),
              const SizedBox(width: 8),
              Text(context.tr('settings.no_children_title'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('settings.no_children_body'),
            style: const TextStyle(
                color: AppColors.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _NarrationCard extends StatelessWidget {
  const _NarrationCard();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(color: AppColors.iconCircleBlue, shape: BoxShape.circle),
                child: const Icon(Icons.record_voice_over_outlined, size: 18),
              ),
              const SizedBox(width: 10),
              Text(context.tr('settings.narration'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 16),
          Text(context.tr('settings.narrator_voice'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.4,
            children: [
              _VoiceButton(label: context.tr('voice.calm_female'), value: NarratorVoice.calmFemale, current: settings.voice, onTap: settings.setVoice),
              _VoiceButton(label: context.tr('voice.gentle_female'), value: NarratorVoice.gentleFemale, current: settings.voice, onTap: settings.setVoice),
              _VoiceButton(label: context.tr('voice.warm_male'), value: NarratorVoice.warmMale, current: settings.voice, onTap: settings.setVoice),
              _VoiceButton(label: context.tr('voice.friendly_child'), value: NarratorVoice.friendlyChild, current: settings.voice, onTap: settings.setVoice),
              _VoiceButton(label: context.tr('voice.soothing_elder'), value: NarratorVoice.soothingElder, current: settings.voice, onTap: settings.setVoice),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(Icons.speed, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(context.tr('settings.reading_speed'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${settings.readingSpeed.toStringAsFixed(1)}x',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(
            value: settings.readingSpeed.clamp(0.5, 2.0),
            min: 0.5,
            max: 2.0,
            divisions: 15,
            activeColor: AppColors.primaryBlueDark,
            inactiveColor: AppColors.cardBorder,
            onChanged: settings.setReadingSpeed,
          ),
          Row(
            children: [
              Text(context.tr('settings.slower'),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              const Spacer(),
              Text(context.tr('settings.faster'),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _VoiceButton extends StatelessWidget {
  final String label;
  final NarratorVoice value;
  final NarratorVoice current;
  final void Function(NarratorVoice) onTap;
  const _VoiceButton({required this.label, required this.value, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return InkWell(
      onTap: () => onTap(value),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBlue : AppColors.softPeach.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _SensoryCard extends StatelessWidget {
  const _SensoryCard();
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    return SoftCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(color: AppColors.iconCircleGreen, shape: BoxShape.circle),
                child: const Icon(Icons.shield_outlined, size: 18),
              ),
              const SizedBox(width: 10),
              Text(context.tr('settings.sensory'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppColors.primaryBlueDark,
            value: settings.autoPlayNext,
            onChanged: settings.setAutoPlayNext,
            title: Text(context.tr('settings.auto_play_next'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(context.tr('settings.auto_play_next_sub'),
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppColors.primaryBlueDark,
            value: settings.readAlong,
            onChanged: settings.setReadAlong,
            title: Text(context.tr('settings.read_along'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(context.tr('settings.read_along_sub'),
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _TextSizeCard extends StatelessWidget {
  const _TextSizeCard();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final scale = settings.textScale;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(
                    color: AppColors.iconCirclePurple, shape: BoxShape.circle),
                child: const Icon(Icons.format_size, size: 18),
              ),
              const SizedBox(width: 10),
              Text(context.tr('settings.text_size'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${(scale * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(context.tr('settings.text_size_sub'),
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          // Shows the chosen size live.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.softPeach.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              context.tr('settings.text_size_preview'),
              style: TextStyle(
                fontSize: 18 * scale,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Slider(
            value: scale.clamp(0.7, 2.0),
            min: 0.7,
            max: 2.0,
            divisions: 13,
            label: '${(scale * 100).round()}%',
            activeColor: AppColors.primaryBlueDark,
            inactiveColor: AppColors.cardBorder,
            onChanged: settings.setTextScale,
          ),
          Row(
            children: [
              Text(context.tr('settings.smaller'),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              const Spacer(),
              Text(context.tr('settings.larger'),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

/* Language toggle (English / Bahasa Malaysia). Changes both the app text
   and the AI story language. */
class _LanguageCard extends StatelessWidget {
  const _LanguageCard();

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageState>();
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(
                    color: AppColors.iconCircleGreen, shape: BoxShape.circle),
                child: const Icon(Icons.translate, size: 18),
              ),
              const SizedBox(width: 10),
              Text(context.tr('settings.language'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('settings.language_sub'),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: AppStrings.supportedCodes.map((code) {
              final selected = code == lang.code;
              final label = AppStrings.languageNames[code] ?? code;
              return InkWell(
                onTap: () => context.read<LanguageState>().setLanguage(code),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primaryBlue
                        : AppColors.softPeach.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.check, size: 16),
                        ),
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _PinChangeCard extends StatefulWidget {
  const _PinChangeCard();
  @override
  State<_PinChangeCard> createState() => _PinChangeCardState();
}

class _PinChangeCardState extends State<_PinChangeCard> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    if (_next.text != _confirm.text) {
      AppSnackbar.warning(context.trRead('settings.pin_mismatch'),
          context: context);
      return;
    }
    setState(() => _busy = true);
    final ok = await context.read<SettingsState>().changePin(
          currentPin: _current.text,
          newPin: _next.text,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      AppSnackbar.success(context.trRead('settings.pin_updated'),
          context: context);
      _current.clear();
      _next.clear();
      _confirm.clear();
    } else {
      AppSnackbar.error(context.trRead('settings.pin_update_failed'),
          context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.iconCirclePeach,
                child: Icon(Icons.lock_outline,
                    size: 18, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 10),
              Text(context.tr('settings.pin_change'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          _pinField(_current, context.tr('settings.current_pin')),
          const SizedBox(height: 10),
          _pinField(_next, context.tr('settings.new_pin')),
          const SizedBox(height: 10),
          _pinField(_confirm, context.tr('settings.confirm_pin')),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.softPeach,
              foregroundColor: AppColors.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _busy ? null : _update,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.tr('settings.update_pin'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _pinField(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 4,
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        suffixIcon: const Icon(Icons.remove_red_eye_outlined,
            color: AppColors.textMuted),
      ),
    );
  }
}
