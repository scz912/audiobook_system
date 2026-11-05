import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/friends_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/back_pill.dart';
import 'friends_tab.dart';

/* Shown right after a caregiver joins the community: everyone already in
   it, each with an add button to send a friend request. */
class MeetFamiliesPage extends StatefulWidget {
  const MeetFamiliesPage({super.key});

  @override
  State<MeetFamiliesPage> createState() => _MeetFamiliesPageState();
}

class _MeetFamiliesPageState extends State<MeetFamiliesPage> {
  @override
  void initState() {
    super.initState();
    // An empty search lists every member.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FriendsState>().search('');
    });
  }

  @override
  Widget build(BuildContext context) {
    final friends = context.watch<FriendsState>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  BackPill(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(context.tr('community.meet_title'),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Text(context.tr('community.meet_body'),
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            Expanded(
              child: friends.searching && friends.searchResults.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : friends.searchResults.isEmpty
                      ? Center(
                          child: Text(context.tr('community.meet_empty'),
                              style: const TextStyle(
                                  color: AppColors.textSecondary)),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          children: [
                            for (final m in friends.searchResults)
                              MemberRow(member: m),
                          ],
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(context.tr('community.meet_done'),
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
}
