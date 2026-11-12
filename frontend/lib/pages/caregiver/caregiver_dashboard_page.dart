import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/insights_overview.dart';
import '../../services/database_service.dart';
import '../../state/profiles_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/adaptive_row.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/stat_sphere_carousel.dart';
import '../../widgets/top_book_tile.dart';
import '../child/audio_player_page.dart';
import '../shared/logout_dialog.dart';
import '../../widgets/shelf_nav_bar.dart';
import 'add_child_dialog.dart';
import '../../widgets/whole_words_text.dart';

class CaregiverDashboardPage extends StatefulWidget {
  final ValueChanged<int>? onJumpToTab;
  const CaregiverDashboardPage({super.key, this.onJumpToTab});

  @override
  State<CaregiverDashboardPage> createState() => _CaregiverDashboardPageState();
}

class _CaregiverDashboardPageState extends State<CaregiverDashboardPage> {
  InsightsOverview? _overview;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  // Engagement and the most-listened books, across all children.
  Future<void> _loadStats() async {
    // Right after Child Mode, let its last session finish saving first.
    await DatabaseService.pendingSessionSaves();
    final resp = await DatabaseService.getInsightsOverview();
    if (!mounted) return;
    if (resp.success && resp.data is InsightsOverview) {
      setState(() => _overview = resp.data as InsightsOverview);
    }
  }

  // Play the book the way the child hears it. Preview mode records nothing.
  void _openBook(TopStory story) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AudioPlayerPage(
          title: story.title,
          audiobookId: story.audiobookId,
          previewMode: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profiles = context.watch<ProfilesState>();
    final stats = [
      StatSphere(
        icon: Icons.people_outline,
        palette: SpherePalette.blue,
        value: '${profiles.totalChildren}',
        label: context.tr('caregiver.stat_total_children'),
      ),
      StatSphere(
        icon: Icons.access_time,
        palette: SpherePalette.green,
        value: '${profiles.totalListeningMinutes}',
        label: context.tr('caregiver.stat_total_minutes'),
      ),
      StatSphere(
        icon: Icons.psychology_outlined,
        palette: SpherePalette.purple,
        value: _overview == null ? '…' : '${_overview!.completionRate}%',
        label: context.tr('caregiver.stat_avg_engagement'),
      ),
    ];
    final topBooks = _overview?.topStories.take(3).toList();

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, shelfBottomSpace(context)),
        children: [
          AdaptiveRow(
            body: WholeWordsText(
              context.tr('caregiver.dashboard'),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.15,
                color: AppColors.textPrimary,
              ),
            ),
            trailing: FilledButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const LogoutDialog(),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(context.tr('caregiver.logout')),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('caregiver.dashboard_subtitle'),
            style:
                const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),

          StatSphereCarousel(spheres: stats),

          const SizedBox(height: 24),
          Text(
            context.tr('caregiver.section_top_books'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          if (profiles.profiles.isEmpty)
            EmptyState(
              icon: Icons.child_care_rounded,
              title: context.tr('caregiver.no_children'),
              subtitle: context.tr('caregiver.empty_subtitle'),
              iconBackground: AppColors.iconCircleBlue,
              iconColor: AppColors.primaryBlueDark,
              action: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const AddChildDialog(),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.tr('caregiver.add_first_child')),
              ),
            )
          else if (topBooks == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (topBooks.isEmpty)
            EmptyState(
              icon: Icons.headphones_rounded,
              title: context.tr('caregiver.no_listening_title'),
              subtitle: context.tr('caregiver.no_listening_body'),
              iconBackground: AppColors.iconCircleGreen,
              iconColor: AppColors.primaryBlueDark,
            )
          else
            for (var i = 0; i < topBooks.length; i++) ...[
              TopBookTile(
                rank: i + 1,
                story: topBooks[i],
                onTap: () => _openBook(topBooks[i]),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}
