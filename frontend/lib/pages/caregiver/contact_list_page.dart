import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/community/contact_settings.dart';
import '../../services/database_service.dart';
import '../../state/chat_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/soft_card.dart';
import '../community/community_widgets.dart';
import '../community/member_profile_page.dart';

enum ContactListKind { favorites, blocked }

/* Settings > Favorite contacts / Blocked contacts. Shown inside the
   Settings tab (the shelf stays below), with a back button to return to
   the main settings. Each person can be un-favorited or unblocked here,
   or tapped to open their profile. */
class ContactListSubpage extends StatefulWidget {
  final ContactListKind kind;
  final VoidCallback onBack;
  const ContactListSubpage({super.key, required this.kind, required this.onBack});

  @override
  State<ContactListSubpage> createState() => _ContactListSubpageState();
}

class _ContactListSubpageState extends State<ContactListSubpage> {
  List<ContactEntry>? _people;
  String? _error;
  final Set<String> _busy = {};

  bool get _favorites => widget.kind == ContactListKind.favorites;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final resp = _favorites
        ? await DatabaseService.favoriteContacts()
        : await DatabaseService.blockedContacts();
    if (!mounted) return;
    setState(() {
      if (resp.success && resp.data is List<ContactEntry>) {
        _people = resp.data as List<ContactEntry>;
        _error = null;
      } else {
        _people = const [];
        _error = resp.error == 'NOT_A_MEMBER'
            ? context.trRead('contacts.join_first')
            : resp.message;
      }
    });
  }

  // Un-favorite or unblock; the person drops off this list.
  Future<void> _remove(ContactEntry entry) async {
    final id = entry.member.caregiverId;
    setState(() => _busy.add(id));
    final resp = await DatabaseService.updateContactSettings(
        id, {_favorites ? 'is_favorite' : 'is_blocked': false});
    if (!mounted) return;
    setState(() => _busy.remove(id));
    if (resp.success) {
      setState(() => _people =
          _people?.where((p) => p.member.caregiverId != id).toList());
      context.read<ChatState>().refresh();
      AppSnackbar.success(
        context.trRead(_favorites ? 'contacts.unfavorited' : 'contacts.unblocked')
            .replaceAll('{name}', entry.member.name),
        context: context,
      );
    } else {
      AppSnackbar.error(resp.message, context: context);
    }
  }

  Future<void> _openProfile(ContactEntry entry) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MemberProfilePage(caregiverId: entry.member.caregiverId),
    ));
    // Settings may have changed there.
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    return PopScope(
      // The phone's back button closes the subpage, not the app.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          BackPill(label: context.tr('common.back'), onTap: widget.onBack),
          const SizedBox(height: 14),
          Text(
            context.tr(_favorites ? 'contacts.favorites_title' : 'contacts.blocked_title'),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(_favorites ? 'contacts.favorites_sub' : 'contacts.blocked_list_sub'),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          if (people == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (people.isEmpty)
            SoftCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(
                      _favorites ? Icons.star_border_rounded : Icons.block_rounded,
                      size: 44,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _error ??
                          context.tr(_favorites
                              ? 'contacts.no_favorites'
                              : 'contacts.no_blocked'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final p in people)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SoftCard(
                  padding: const EdgeInsets.all(12),
                  onTap: () => _openProfile(p),
                  child: Row(
                    children: [
                      MemberAvatar(
                        emoji: p.member.avatarEmoji,
                        colorHex: p.member.avatarColor,
                        size: 46,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(p.member.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                      if (_busy.contains(p.member.caregiverId))
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (_favorites)
                        IconButton(
                          tooltip: context.tr('contacts.remove_favorite'),
                          onPressed: () => _remove(p),
                          icon: const Icon(Icons.star_rounded,
                              color: Color(0xFFE0A100)),
                        )
                      else
                        TextButton(
                          onPressed: () => _remove(p),
                          child: Text(context.tr('contacts.unblock'),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
