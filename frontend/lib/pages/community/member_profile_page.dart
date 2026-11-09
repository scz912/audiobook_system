import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/community/contact_settings.dart';
import '../../models/community/member.dart';
import '../../services/database_service.dart';
import '../../state/chat_state.dart';
import '../../state/friends_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/soft_card.dart';
import 'chat_background_page.dart';
import 'chat_thread_page.dart';
import 'community_widgets.dart';

// A member's profile: avatar, bio, shared count, and add-friend / message actions.
class MemberProfilePage extends StatefulWidget {
  final String caregiverId;
  const MemberProfilePage({super.key, required this.caregiverId});

  @override
  State<MemberProfilePage> createState() => _MemberProfilePageState();
}

class _MemberProfilePageState extends State<MemberProfilePage> {
  Member? _member;
  // My settings for this person. Null for my own profile (or if they
  // couldn't load), which hides the settings card.
  ContactSettings? _settings;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      DatabaseService.memberProfile(widget.caregiverId),
      DatabaseService.contactSettings(widget.caregiverId),
    ]);
    if (!mounted) return;
    final resp = results[0];
    final settings = results[1];
    setState(() {
      _member = resp.success && resp.data is Member ? resp.data as Member : null;
      _settings = settings.success && settings.data is ContactSettings
          ? settings.data as ContactSettings
          : null;
      _loading = false;
    });
  }

  /* Flip favorite / mute / block. The switch moves straight away; if the
     server says no, it moves back. */
  Future<void> _setFlag(String key, bool value) async {
    final before = _settings;
    if (before == null) return;
    setState(() => _settings = switch (key) {
          'is_favorite' => before.copyWith(isFavorite: value),
          'is_muted' => before.copyWith(isMuted: value),
          _ => before.copyWith(isBlocked: value),
        });
    final resp = await DatabaseService.updateContactSettings(
        widget.caregiverId, {key: value});
    if (!mounted) return;
    if (resp.success && resp.data is ContactSettings) {
      setState(() => _settings = resp.data as ContactSettings);
      // The chat list shows favorites, mutes and blocks.
      context.read<ChatState>().refresh();
    } else {
      setState(() => _settings = before);
      AppSnackbar.error(resp.message, context: context);
    }
  }

  Future<void> _toggleBlock(bool block) async {
    if (block) {
      final name = _member?.name ?? '';
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(ctx.tr('contacts.block_title').replaceAll('{name}', name)),
          content: Text(ctx.tr('contacts.block_body'),
              style: const TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.tr('common.cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.tr('contacts.block')),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await _setFlag('is_blocked', block);
  }

  Future<void> _pickBackground() async {
    final settings = _settings;
    if (settings == null) return;
    final saved = await Navigator.of(context).push<ContactSettings>(
      MaterialPageRoute(
        builder: (_) => ChatBackgroundPage(
          contactId: widget.caregiverId,
          contactName: _member?.name ?? '',
          current: settings.background,
        ),
      ),
    );
    if (saved != null && mounted) {
      setState(() => _settings = saved);
      context.read<ChatState>().refresh();
    }
  }

  Future<void> _addFriend() async {
    setState(() => _busy = true);
    final ok = await context.read<FriendsState>().sendRequest(widget.caregiverId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      AppSnackbar.success(context.trRead('community.request_sent'), context: context);
      _load();
    }
  }

  Future<void> _message() async {
    setState(() => _busy = true);
    final resp = await DatabaseService.startDirectChat(widget.caregiverId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (resp.success && resp.data != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatThreadPage(conversation: resp.data),
      ));
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
                  Text(context.tr('community.profile'),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _member == null
                      ? Center(
                          child: Text(context.tr('community.profile_load_failed'),
                              style: const TextStyle(color: AppColors.textSecondary)))
                      : _body(_member!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(Member member) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const SizedBox(height: 12),
        Center(
          child: MemberAvatar(
            emoji: member.avatarEmoji,
            colorHex: member.avatarColor,
            size: 96,
          ),
        ),
        const SizedBox(height: 14),
        Text(member.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        if (member.bio != null && member.bio!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(member.bio!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4)),
        ],
        const SizedBox(height: 16),
        SoftCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Stat(
                  value: '${member.sharedCount}',
                  label: context.tr('community.shared_stories')),
              Container(width: 1, height: 34, color: AppColors.cardBorder),
              _Stat(
                value: member.relation == 'friends'
                    ? context.tr('community.friends')
                    : '-',
                label: context.tr('community.status'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _friendButton(member)),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  side: const BorderSide(color: AppColors.cardBorder),
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _busy ? null : _message,
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: Text(context.tr('community.message')),
              ),
            ),
          ],
        ),
        if (_settings != null) ...[
          const SizedBox(height: 18),
          _ContactSettingsCard(
            settings: _settings!,
            onFavorite: (v) => _setFlag('is_favorite', v),
            onMute: (v) => _setFlag('is_muted', v),
            onBlock: _toggleBlock,
            onBackground: _pickBackground,
          ),
        ],
      ],
    );
  }

  Widget _friendButton(Member member) {
    if (member.relation == 'friends') {
      return FilledButton.icon(
        style: _filledStyle(AppColors.softMintDark),
        onPressed: null,
        icon: const Icon(Icons.people_rounded),
        label: Text(context.tr('community.friends')),
      );
    }
    if (member.relation == 'request_sent') {
      return FilledButton.icon(
        style: _filledStyle(AppColors.cardBorder),
        onPressed: null,
        icon: const Icon(Icons.hourglass_top_rounded),
        label: Text(context.tr('community.requested')),
      );
    }
    return FilledButton.icon(
      style: _filledStyle(AppColors.primaryBlue),
      onPressed: _busy ? null : _addFriend,
      icon: const Icon(Icons.person_add_alt_1_rounded),
      label: Text(context.tr('community.add_friend')),
    );
  }

  ButtonStyle _filledStyle(Color color) => FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}

/* Favorite, mute, chat background and block for this contact. Only this
   caregiver sees these; the other person isn't told. */
class _ContactSettingsCard extends StatelessWidget {
  final ContactSettings settings;
  final ValueChanged<bool> onFavorite;
  final ValueChanged<bool> onMute;
  final ValueChanged<bool> onBlock;
  final VoidCallback onBackground;
  const _ContactSettingsCard({
    required this.settings,
    required this.onFavorite,
    required this.onMute,
    required this.onBlock,
    required this.onBackground,
  });

  String _backgroundLabel(BuildContext context) {
    switch (settings.background.isNone ? 'none' : settings.background.type) {
      case 'color':
        return context.tr('contacts.bg_color');
      case 'gradient':
        return context.tr('contacts.gradient');
      case 'image':
        return context.tr('contacts.my_picture');
      default:
        return context.tr('contacts.default');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget icon(IconData i, Color bg, Color fg) => Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(i, size: 20, color: fg),
        );
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          SwitchListTile(
            secondary: icon(
              settings.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              AppColors.softYellow,
              const Color(0xFFE0A100),
            ),
            title: Text(context.tr('contacts.favorite'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(context.tr('contacts.favorite_sub')),
            value: settings.isFavorite,
            onChanged: onFavorite,
          ),
          SwitchListTile(
            secondary: icon(
              settings.isMuted
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_none_rounded,
              AppColors.iconCircleBlue,
              AppColors.primaryBlueDark,
            ),
            title: Text(context.tr('contacts.mute'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(context.tr('contacts.mute_sub')),
            value: settings.isMuted,
            onChanged: onMute,
          ),
          ListTile(
            leading: icon(Icons.wallpaper_rounded, AppColors.iconCirclePurple,
                const Color(0xFF6B5B95)),
            title: Text(context.tr('contacts.chat_background'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(_backgroundLabel(context)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onBackground,
          ),
          SwitchListTile(
            secondary: icon(Icons.block_rounded, const Color(0xFFF8DADA),
                AppColors.danger),
            title: Text(context.tr('contacts.block'),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.danger)),
            subtitle: Text(context.tr('contacts.block_sub')),
            value: settings.isBlocked,
            activeThumbColor: AppColors.danger,
            onChanged: onBlock,
          ),
        ],
      ),
    );
  }
}
