import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/community/member.dart';
import '../../services/database_service.dart';
import '../../state/friends_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/soft_card.dart';
import 'chat_thread_page.dart';
import 'community_widgets.dart';

// Create a group chat: give it a name and pick friends to add.
class NewGroupPage extends StatefulWidget {
  const NewGroupPage({super.key});

  @override
  State<NewGroupPage> createState() => _NewGroupPageState();
}

class _NewGroupPageState extends State<NewGroupPage> {
  final _titleCtrl = TextEditingController();
  final Set<String> _selected = {};
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FriendsState>().refresh();
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      AppSnackbar.warning('Give the group a name', context: context);
      return;
    }
    if (_selected.isEmpty) {
      AppSnackbar.warning('Pick at least one friend', context: context);
      return;
    }
    setState(() => _creating = true);
    final resp = await DatabaseService.createGroupChat(title, _selected.toList());
    if (!mounted) return;
    setState(() => _creating = false);
    if (resp.success && resp.data != null) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ChatThreadPage(conversation: resp.data),
      ));
    } else {
      AppSnackbar.error(resp.message, context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = context.watch<FriendsState>();
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
                  const Text('New group',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(hintText: 'Group name'),
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Add friends',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: friends.friends.isEmpty
                  ? const Center(
                      child: Text('Add some friends first.',
                          style: TextStyle(color: AppColors.textSecondary)))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: friends.friends.map(_friendTile).toList(),
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
                  onPressed: _creating ? null : _create,
                  child: _creating
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('Create group (${_selected.length})',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _friendTile(Member friend) {
    final picked = _selected.contains(friend.caregiverId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        color: picked ? AppColors.iconCircleBlue : null,
        padding: const EdgeInsets.all(10),
        onTap: () => setState(() {
          if (picked) {
            _selected.remove(friend.caregiverId);
          } else {
            _selected.add(friend.caregiverId);
          }
        }),
        child: Row(
          children: [
            MemberAvatar(
                emoji: friend.avatarEmoji, colorHex: friend.avatarColor, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Text(friend.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Icon(
              picked
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: picked ? AppColors.primaryBlueDark : AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
