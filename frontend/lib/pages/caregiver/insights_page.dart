import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/ai_suggestion.dart';
import '../../models/insights_overview.dart';
import '../../services/api_service.dart';
import '../../services/database_service.dart';
import '../../state/profiles_state.dart';
import '../../state/settings_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/soft_card.dart';
import '../../widgets/stat_card.dart';

class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  InsightsOverview _data = InsightsOverview.empty();
  bool _loading = true;
  String? _error;
  // null = all children (the default), else the one child we're showing.
  // Kept across rebuilds so the chip choice sticks.
  String? _selectedChildId;

  // AI tips for the selected child. Tips are per-child, so this only loads
  // when one child is selected.
  AiSuggestion? _suggestions;
  bool _suggestionsLoading = false;
  bool _analyzing = false;

  static const _moodEmoji = {
    'happy': '😊',
    'calm': '😌',
    'curious': '🤔',
    'sleepy': '😴',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final ApiResponse resp = await DatabaseService.getInsightsOverview(
      childId: _selectedChildId,
    );
    if (!mounted) return;
    if (resp.success && resp.data is InsightsOverview) {
      setState(() {
        _data = resp.data as InsightsOverview;
        _loading = false;
      });
    } else {
      setState(() {
        _data = InsightsOverview.empty();
        _error = resp.message;
        _loading = false;
      });
    }
  }

  void _selectChild(String? childId) {
    if (_selectedChildId == childId) return;
    setState(() {
      _selectedChildId = childId;
      // Clear the old child's tips while we load the new one's.
      _suggestions = null;
    });
    _load();
    if (childId != null) {
      _loadSuggestions(childId);
    }
  }

  Future<void> _loadSuggestions(String childId) async {
    setState(() => _suggestionsLoading = true);
    final resp = await DatabaseService.getSuggestions(childId);
    if (!mounted || _selectedChildId != childId) return;
    setState(() {
      _suggestions = resp.success && resp.data is AiSuggestion
          ? resp.data as AiSuggestion
          : null;
      _suggestionsLoading = false;
    });
  }

  Future<void> _runAnalysis(String childId) async {
    setState(() => _analyzing = true);
    final resp = await DatabaseService.analyseListening(childId);
    if (!mounted || _selectedChildId != childId) return;
    setState(() {
      if (resp.success && resp.data is AiSuggestion) {
        _suggestions = resp.data as AiSuggestion;
      }
      _analyzing = false;
    });
    if (!resp.success && mounted) {
      AppSnackbar.error(resp.message, context: context);
    } else if (mounted &&
        _suggestions != null &&
        _suggestions!.isStale) {
      AppSnackbar.warning(
        context.tr('insights.suggestions_stale'),
        context: context,
      );
    }
  }

  Future<void> _acceptItem(
    String childId,
    AiSuggestionItem item, {
    dynamic overrideValue,
  }) async {
    final resp = await DatabaseService.applySuggestion(
      childId: childId,
      itemId: item.id,
      overrideValue: overrideValue,
    );
    if (!mounted) return;
    if (resp.success && resp.data is AiSuggestion) {
      setState(() => _suggestions = resp.data as AiSuggestion);
      // The value is in child_settings now — re-load so the player sees it.
      // ignore: use_build_context_synchronously
      await context.read<SettingsState>().loadForChild(childId);
    } else {
      AppSnackbar.error(resp.message, context: context);
    }
  }

  Future<void> _dismissItem(String childId, AiSuggestionItem item) async {
    final resp = await DatabaseService.dismissSuggestion(
      childId: childId,
      itemId: item.id,
    );
    if (!mounted) return;
    if (resp.success && resp.data is AiSuggestion) {
      setState(() => _suggestions = resp.data as AiSuggestion);
    } else {
      AppSnackbar.error(resp.message, context: context);
    }
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  String _formatAvg(double minutes) {
    if (minutes <= 0) return '0m';
    if (minutes < 1) return '<1m';
    return '${minutes.toStringAsFixed(minutes >= 10 ? 0 : 1)}m';
  }

  String _moodLabel(BuildContext context, String? mood) {
    if (mood == null) return '—';
    return context.tr('insights.mood.$mood');
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(
            context.tr('insights.title'),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('insights.subtitle'),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          _ChildScopeSelector(
            selectedChildId: _selectedChildId,
            onSelect: _selectChild,
            viewingLabel: context.tr('insights.viewing'),
            allLabel: context.tr('insights.viewing_all'),
          ),
          const SizedBox(height: 16),
          if (_selectedChildId != null) ...[
            _SuggestionsCard(
              suggestion: _suggestions,
              loading: _suggestionsLoading,
              analyzing: _analyzing,
              onRunAnalysis: () => _runAnalysis(_selectedChildId!),
              onAccept: (item) =>
                  _acceptItem(_selectedChildId!, item),
              onEditAccept: (item, value) =>
                  _acceptItem(_selectedChildId!, item, overrideValue: value),
              onDismiss: (item) => _dismissItem(_selectedChildId!, item),
            ),
            const SizedBox(height: 16),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            EmptyState(
              icon: Icons.cloud_off_rounded,
              title: context.tr('insights.load_error_title'),
              subtitle: context.tr('insights.load_error_body'),
              iconBackground: AppColors.softPeach,
              iconColor: AppColors.warning,
            )
          else if (_data.totalSessions == 0)
            EmptyState(
              icon: Icons.insights_rounded,
              title: context.tr('insights.empty_title'),
              subtitle: context.tr('insights.empty_body'),
              iconBackground: AppColors.iconCircleGreen,
              iconColor: AppColors.success,
            )
          else ...[
            _buildOverviewGrid(context),
            const SizedBox(height: 20),
            _SectionHeader(
              title: context.tr('insights.this_week'),
              subtitle: context.tr('insights.this_week_sub'),
            ),
            const SizedBox(height: 10),
            SoftCard(
              child: _WeekChart(
                days: _data.lastSevenDays,
                minutesShort: context.tr('insights.minutes_short'),
              ),
            ),
            if (_hasMoodData) ...[
              const SizedBox(height: 20),
              _SectionHeader(title: context.tr('insights.mood_breakdown')),
              const SizedBox(height: 10),
              SoftCard(
                child: _MoodBreakdown(
                  breakdown: _data.moodBreakdown,
                  label: (m) => _moodLabel(context, m),
                ),
              ),
            ],
            if (_data.topStories.isNotEmpty) ...[
              const SizedBox(height: 20),
              _SectionHeader(
                title: context.tr('insights.top_stories'),
                subtitle: context.tr('insights.top_stories_sub'),
              ),
              const SizedBox(height: 10),
              SoftCard(
                child: _TopStoriesList(
                  stories: _data.topStories,
                  minutesShort: context.tr('insights.minutes_short'),
                  playsShort: context.tr('insights.plays_short'),
                ),
              ),
            ],
            if (_data.recentSessions.isNotEmpty) ...[
              const SizedBox(height: 20),
              _SectionHeader(
                title: context.tr('insights.recent_activity'),
                subtitle: context.tr('insights.recent_activity_sub'),
              ),
              const SizedBox(height: 10),
              SoftCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: _RecentList(
                  sessions: _data.recentSessions,
                  completedLabel:
                      context.tr('insights.completed_badge'),
                  leftOffLabel: context.tr('insights.left_off_badge'),
                  minutesShort: context.tr('insights.minutes_short'),
                  moodLabel: (m) => _moodLabel(context, m),
                ),
              ),
            ],
            const SizedBox(height: 20),
            _SectionHeader(title: context.tr('insights.per_child')),
            const SizedBox(height: 10),
            for (final c in _data.children) ...[
              _ChildInsightCard(
                child: c,
                minutesLabel: _formatMinutes(c.listeningMinutes),
                avgLabel: _formatAvg(c.avgSessionMinutes),
                moodEmoji: _moodEmoji[c.topMood],
                moodLabel: _moodLabel(context, c.topMood),
                streakDaysShort: context.tr('insights.streak_days_short'),
                completionLabel: context.tr('insights.completion'),
                finishedLabel: context.tr('insights.finished'),
                genreLabel: context.tr('insights.genre'),
                avgLabelText: context.tr('insights.avg_session'),
                streakLabelText: context.tr('insights.streak'),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewGrid(BuildContext context) {
    final cards = <_StatSpec>[
      _StatSpec(
        icon: Icons.headphones,
        iconBackground: AppColors.iconCircleBlue,
        value: _formatMinutes(_data.totalListeningMinutes),
        label: context.tr('insights.total_minutes'),
      ),
      _StatSpec(
        icon: Icons.play_circle_outline,
        iconBackground: AppColors.iconCircleGreen,
        value: '${_data.totalSessions}',
        label: context.tr('insights.total_sessions'),
      ),
      _StatSpec(
        icon: Icons.task_alt,
        iconBackground: AppColors.iconCirclePeach,
        value: '${_data.completionRate}%',
        label: context.tr('insights.stories_completed'),
      ),
      _StatSpec(
        icon: Icons.emoji_emotions_outlined,
        iconBackground: AppColors.iconCirclePurple,
        value: _data.topMood != null
            ? '${_moodEmoji[_data.topMood] ?? ''} ${_moodLabel(context, _data.topMood)}'
            : '—',
        label: context.tr('insights.top_mood'),
      ),
      _StatSpec(
        icon: Icons.access_time_rounded,
        iconBackground: AppColors.softMint,
        value: _formatAvg(_data.avgSessionMinutes),
        label: context.tr('insights.avg_session'),
      ),
      _StatSpec(
        icon: Icons.local_fire_department_rounded,
        iconBackground: AppColors.softPeach,
        value:
            '${_data.streakDays}${context.tr('insights.streak_days_short')}',
        label: context.tr('insights.streak'),
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      // Just shy of square — fits the two-line labels with no gap below.
      childAspectRatio: 1.05,
      children: cards
          .map((s) => StatCard(
                icon: s.icon,
                iconBackground: s.iconBackground,
                value: s.value,
                label: s.label,
              ))
          .toList(),
    );
  }

  bool get _hasMoodData => _data.moodBreakdown.values.any((v) => v > 0);
}

/* Row to pick whose insights to show — "All children" plus one chip per
   child. Tapping a chip reloads the insights for that child. */
class _ChildScopeSelector extends StatelessWidget {
  final String? selectedChildId;
  final void Function(String? childId) onSelect;
  final String viewingLabel;
  final String allLabel;
  const _ChildScopeSelector({
    required this.selectedChildId,
    required this.onSelect,
    required this.viewingLabel,
    required this.allLabel,
  });

  @override
  Widget build(BuildContext context) {
    final profiles = context.watch<ProfilesState>().profiles;
    if (profiles.isEmpty) return const SizedBox.shrink();
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_alt_outlined,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(viewingLabel,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ScopeChip(
                  emoji: '👨‍👩‍👧',
                  label: allLabel,
                  color: AppColors.iconCircleBlue,
                  selected: selectedChildId == null,
                  onTap: () => onSelect(null),
                ),
                const SizedBox(width: 8),
                for (final p in profiles) ...[
                  _ScopeChip(
                    emoji: p.avatarEmoji,
                    label: p.name,
                    color: p.avatarColor,
                    selected: selectedChildId == p.childId,
                    onTap: () => onSelect(p.childId),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ScopeChip({
    required this.emoji,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBlue : color.withValues(alpha: 0.6),
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
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight:
                    selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatSpec {
  final IconData icon;
  final Color iconBackground;
  final String value;
  final String label;
  const _StatSpec({
    required this.icon,
    required this.iconBackground,
    required this.value,
    required this.label,
  });
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
        ],
      ],
    );
  }
}

// Small bar chart of listening minutes for the last 7 days.
class _WeekChart extends StatelessWidget {
  final List<DayMinutes> days;
  final String minutesShort;
  const _WeekChart({required this.days, required this.minutesShort});

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(context.tr('insights.no_activity'),
            style: const TextStyle(color: AppColors.textSecondary)),
      );
    }
    final maxMinutes = days
        .map((d) => d.minutes)
        .fold<int>(0, (a, b) => b > a ? b : a)
        .clamp(1, 1 << 30);
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: days.map((d) {
          final frac = d.minutes / maxMinutes;
          final isToday = d == days.last;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    d.minutes == 0 ? '' : '${d.minutes}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Bar grows up from the bottom.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final height = (c.maxHeight * frac).clamp(2.0, c.maxHeight);
                        return Align(
                          alignment: Alignment.bottomCenter,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: height,
                            decoration: BoxDecoration(
                              color: isToday
                                  ? AppColors.primaryBlueDark
                                  : AppColors.primaryBlue,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    d.dayLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MoodBreakdown extends StatelessWidget {
  final Map<String, int> breakdown;
  final String Function(String) label;
  const _MoodBreakdown({required this.breakdown, required this.label});

  static const _order = ['happy', 'calm', 'curious', 'sleepy'];
  static const _emoji = {
    'happy': '😊',
    'calm': '😌',
    'curious': '🤔',
    'sleepy': '😴',
  };
  static const _color = {
    'happy': AppColors.moodHappy,
    'calm': AppColors.moodCalm,
    'curious': AppColors.moodCurious,
    'sleepy': AppColors.moodSleepy,
  };

  @override
  Widget build(BuildContext context) {
    final total = breakdown.values.fold<int>(0, (a, b) => a + b);
    return Column(
      children: _order.map((mood) {
        final count = breakdown[mood] ?? 0;
        final fraction = total == 0 ? 0.0 : count / total;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Text(_emoji[mood] ?? '', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              SizedBox(
                width: 84,
                child: Text(
                  label(mood),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 10,
                    backgroundColor: AppColors.background,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(_color[mood]!),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 28,
                child: Text(
                  '$count',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _TopStoriesList extends StatelessWidget {
  final List<TopStory> stories;
  final String minutesShort;
  final String playsShort;
  const _TopStoriesList({
    required this.stories,
    required this.minutesShort,
    required this.playsShort,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(stories.length, (i) {
        final s = stories[i];
        return Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryBlueDark,
                    fontSize: 18,
                  ),
                ),
              ),
              _CoverThumb(url: s.coverImage),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${s.minutes} $minutesShort • ${s.plays} $playsShort',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _RecentList extends StatelessWidget {
  final List<RecentSession> sessions;
  final String completedLabel;
  final String leftOffLabel;
  final String minutesShort;
  final String Function(String) moodLabel;
  const _RecentList({
    required this.sessions,
    required this.completedLabel,
    required this.leftOffLabel,
    required this.minutesShort,
    required this.moodLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < sessions.length; i++) ...[
          _RecentTile(
            session: sessions[i],
            completedLabel: completedLabel,
            leftOffLabel: leftOffLabel,
            minutesShort: minutesShort,
            moodLabel: moodLabel,
          ),
          if (i != sessions.length - 1)
            const Divider(height: 18, color: AppColors.cardBorder),
        ],
      ],
    );
  }
}

class _RecentTile extends StatelessWidget {
  final RecentSession session;
  final String completedLabel;
  final String leftOffLabel;
  final String minutesShort;
  final String Function(String) moodLabel;
  const _RecentTile({
    required this.session,
    required this.completedLabel,
    required this.leftOffLabel,
    required this.minutesShort,
    required this.moodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final completed = session.completed;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Child avatar
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: session.childColor,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(session.childEmoji,
              style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.childName,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 1),
              Text(
                session.audiobookTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _MiniChip(
                    icon: Icons.access_time,
                    text: '${session.durationMinutes} $minutesShort',
                  ),
                  _MiniChip(
                    icon: completed
                        ? Icons.check_circle_outline
                        : Icons.adjust_rounded,
                    text: completed ? completedLabel : leftOffLabel,
                    color: completed
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                  if (session.mood != null)
                    _MiniChip(
                      icon: Icons.emoji_emotions_outlined,
                      text: moodLabel(session.mood!),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _shortWhen(session.at),
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  String _shortWhen(String iso) {
    // "2026-05-29 13:14" → "May 29, 13:14" so it fits the small slot.
    try {
      final parts = iso.split(' ');
      if (parts.length != 2) return iso;
      final date = DateTime.parse('${parts[0]}T${parts[1]}:00');
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[date.month - 1]} ${date.day}, ${parts[1]}';
    } catch (_) {
      return iso;
    }
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _MiniChip({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _CoverThumb extends StatelessWidget {
  final String? url;
  const _CoverThumb({this.url});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.softLavender,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.menu_book_outlined,
          size: 18, color: AppColors.textPrimary),
    );
    final src = url;
    if (src == null || src.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        src,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        cacheWidth: 120,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

class _ChildInsightCard extends StatelessWidget {
  final ChildInsight child;
  final String minutesLabel;
  final String avgLabel;
  final String? moodEmoji;
  final String moodLabel;
  final String streakDaysShort;
  final String completionLabel;
  final String finishedLabel;
  final String genreLabel;
  final String avgLabelText;
  final String streakLabelText;

  const _ChildInsightCard({
    required this.child,
    required this.minutesLabel,
    required this.avgLabel,
    required this.moodEmoji,
    required this.moodLabel,
    required this.streakDaysShort,
    required this.completionLabel,
    required this.finishedLabel,
    required this.genreLabel,
    required this.avgLabelText,
    required this.streakLabelText,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration:
                    BoxDecoration(color: child.avatarColor, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(child.avatarEmoji,
                    style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(child.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      '$minutesLabel • ${child.sessions} session${child.sessions == 1 ? '' : 's'}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (child.topMood != null)
                _Badge(
                  label: '${moodEmoji ?? ''} $moodLabel',
                  color: AppColors.iconCirclePurple,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: completionLabel,
                  value: '${child.completionRate}%',
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: finishedLabel,
                  value: '${child.completed}/${child.sessions}',
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: avgLabelText.replaceAll('\n', ' '),
                  value: avgLabel,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: streakLabelText.replaceAll('\n', ' '),
                  value: '${child.streakDays}$streakDaysShort',
                ),
              ),
            ],
          ),
          if ((child.favoriteGenre ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.local_offer_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  '$genreLabel: ${child.favoriteGenre}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

// AI listening-behaviour suggestions

/* An icon and tint per setting, so each tip tile looks distinct instead of
   a wall of grey text. */
class _SettingVisual {
  final IconData icon;
  final Color tint;
  const _SettingVisual(this.icon, this.tint);
}

_SettingVisual _visualFor(String key) {
  switch (key) {
    case 'reading_speed':
      return const _SettingVisual(Icons.speed_rounded, AppColors.iconCircleBlue);
    case 'narrator_voice':
      return const _SettingVisual(
          Icons.record_voice_over_rounded, AppColors.iconCirclePurple);
    case 'volume':
      return const _SettingVisual(Icons.volume_up_rounded, AppColors.iconCircleGreen);
    case 'text_scale':
      return const _SettingVisual(Icons.text_fields_rounded, AppColors.iconCirclePeach);
    case 'reduced_animations':
      return const _SettingVisual(
          Icons.motion_photos_pause_rounded, AppColors.softLavender);
    case 'auto_play_next':
      return const _SettingVisual(Icons.skip_next_rounded, AppColors.softMint);
    case 'read_along':
      return const _SettingVisual(Icons.format_color_text_rounded, AppColors.softPeach);
    default:
      return const _SettingVisual(Icons.tune_rounded, AppColors.softLavender);
  }
}

/* "5 min ago" style time, with the full timestamp in the tooltip —
   friendlier than a raw timestamp. */
String _relativeWhen(BuildContext context, DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inSeconds < 60) return context.tr('insights.time_just_now');
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} ${context.tr('insights.time_minutes_ago')}';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} ${context.tr('insights.time_hours_ago')}';
  }
  return '${diff.inDays} ${context.tr('insights.time_days_ago')}';
}

String _absoluteWhen(DateTime when) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[when.month - 1]} ${when.day}, '
      '${when.hour.toString().padLeft(2, '0')}:'
      '${when.minute.toString().padLeft(2, '0')}';
}

/* Shows Gemini's tips with Accept / Edit & accept / Dismiss on each one.
   Always there when a child is selected, so "Run AI analysis" is visible
   even before the first run. */
class _SuggestionsCard extends StatelessWidget {
  final AiSuggestion? suggestion;
  final bool loading;
  final bool analyzing;
  final VoidCallback onRunAnalysis;
  final void Function(AiSuggestionItem item) onAccept;
  final void Function(AiSuggestionItem item, dynamic value) onEditAccept;
  final void Function(AiSuggestionItem item) onDismiss;

  const _SuggestionsCard({
    required this.suggestion,
    required this.loading,
    required this.analyzing,
    required this.onRunAnalysis,
    required this.onAccept,
    required this.onEditAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final pendingCount = s == null
        ? 0
        : s.items.where((i) => i.isPending).length;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            pendingCount: pendingCount,
            hasItems: s != null && s.items.isNotEmpty,
          ),
          const SizedBox(height: 16),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _buildBody(context),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final s = suggestion;
    final hasItems = s != null && s.items.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s != null && s.isStale)
          _InfoBanner(
            color: AppColors.softPeach,
            icon: Icons.cloud_off_rounded,
            iconColor: AppColors.warning,
            text: context.tr('insights.suggestions_stale'),
          ),
        if (s != null && s.isLowConfidence) ...[
          if (s.isStale) const SizedBox(height: 8),
          _InfoBanner(
            color: AppColors.softLavender,
            icon: Icons.info_outline_rounded,
            iconColor: AppColors.textPrimary,
            text: context.tr('insights.suggestions_low_confidence'),
          ),
        ],
        if (hasItems) ...[
          if (s.isStale || s.isLowConfidence) const SizedBox(height: 14),
          for (var i = 0; i < s.items.length; i++) ...[
            _SuggestionTile(
              item: s.items[i],
              onAccept: () => onAccept(s.items[i]),
              onEditAccept: (v) => onEditAccept(s.items[i], v),
              onDismiss: () => onDismiss(s.items[i]),
            ),
            if (i != s.items.length - 1) const SizedBox(height: 12),
          ],
        ] else ...[
          if (s != null && (s.isStale || s.isLowConfidence))
            const SizedBox(height: 14),
          _EmptyState(),
        ],
        const SizedBox(height: 18),
        _Footer(
          generatedAt: s?.generatedAt,
          analyzing: analyzing,
          hasItems: hasItems,
          onRunAnalysis: onRunAnalysis,
        ),
      ],
    );
  }
}

/* Top of the card — AI badge, title, and a chip showing how many tips
   still need attention. */
class _Header extends StatelessWidget {
  final int pendingCount;
  final bool hasItems;
  const _Header({required this.pendingCount, required this.hasItems});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryBlue, AppColors.primaryBlueDark],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.auto_awesome_rounded,
              size: 22, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('insights.suggestions_title'),
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 2),
              Text(
                context.tr('insights.suggestions_sub'),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        if (hasItems) ...[
          const SizedBox(width: 8),
          _PendingChip(count: pendingCount),
        ],
      ],
    );
  }
}

class _PendingChip extends StatelessWidget {
  final int count;
  const _PendingChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final allResolved = count == 0;
    final bg = allResolved
        ? AppColors.iconCircleGreen
        : AppColors.softPeach;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            allResolved ? Icons.check_circle_rounded : Icons.fiber_manual_record,
            size: 10,
            color: allResolved ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 4),
          Text(
            allResolved
                ? context.tr('insights.all_resolved')
                : '$count ${context.tr(count == 1 ? 'insights.pending_count_one' : 'insights.pending_count_many')}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// Bottom of the card — the time stamp and the Run/Refresh button.
class _Footer extends StatelessWidget {
  final DateTime? generatedAt;
  final bool analyzing;
  final bool hasItems;
  final VoidCallback onRunAnalysis;
  const _Footer({
    required this.generatedAt,
    required this.analyzing,
    required this.hasItems,
    required this.onRunAnalysis,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (generatedAt != null) ...[
          Tooltip(
            message: _absoluteWhen(generatedAt!),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.history_rounded,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  _relativeWhen(context, generatedAt!),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
        const Spacer(),
        FilledButton.icon(
          onPressed: analyzing ? null : onRunAnalysis,
          icon: analyzing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Icon(
                  hasItems
                      ? Icons.refresh_rounded
                      : Icons.auto_awesome_rounded,
                  size: 18),
          label: Text(analyzing
              ? context.tr('insights.analyzing')
              : (hasItems
                  ? context.tr('insights.refresh_analysis')
                  : context.tr('insights.run_analysis'))),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
      ],
    );
  }
}

/* Shown when a child is selected but no analysis has run yet — a friendly
   icon and the "Run AI analysis" prompt. */
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.iconCirclePurple,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.auto_awesome_outlined,
                size: 28, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),
          Text(
            context.tr('insights.no_suggestions_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              context.tr('insights.no_suggestions_body'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final Color color;
  final Color iconColor;
  final IconData icon;
  final String text;
  const _InfoBanner({
    required this.color,
    required this.iconColor,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final AiSuggestionItem item;
  final VoidCallback onAccept;
  final void Function(dynamic value) onEditAccept;
  final VoidCallback onDismiss;

  const _SuggestionTile({
    required this.item,
    required this.onAccept,
    required this.onEditAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(item.settingKey);
    final settingLabel = context.tr('insights.setting.${item.settingKey}');
    final suggested = _renderValue(context, item.settingKey, item.suggestedValue);
    final current = item.currentValue == null
        ? null
        : _renderValue(context, item.settingKey, item.currentValue);
    final resolved = !item.isPending;

    // Resolved tiles fade back so attention falls on the pending ones.
    return Opacity(
      opacity: resolved ? 0.55 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: setting icon, name, and resolved badge.
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: visual.tint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(visual.icon,
                      size: 18, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    settingLabel,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
                if (resolved) _StatusBadge(item: item),
              ],
            ),
            const SizedBox(height: 12),
            // Now vs. suggested.
            _ValueComparison(
              currentLabel: context.tr('insights.current_value'),
              suggestedLabel: context.tr('insights.suggested_value'),
              current: current,
              suggested: suggested,
              tint: visual.tint,
            ),
            const SizedBox(height: 12),
            // Reason — soft callout with a lightbulb.
            _ReasonCallout(text: item.reason),
            if (item.isPending) ...[
              const SizedBox(height: 12),
              _ActionBar(
                onAccept: onAccept,
                onEditAccept: () async {
                  final newValue = await _openEditor(context);
                  if (newValue != null) onEditAccept(newValue);
                },
                onDismiss: onDismiss,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<dynamic> _openEditor(BuildContext context) {
    return showDialog<dynamic>(
      context: context,
      builder: (ctx) => _EditValueDialog(item: item),
    );
  }

  static String _renderValue(BuildContext context, String key, dynamic v) {
    switch (key) {
      case 'narrator_voice':
        return context.tr('voice.${v.toString()}');
      case 'reduced_animations':
      case 'auto_play_next':
      case 'read_along':
        final on = v == true || v == 'true' || v == 1;
        return on
            ? context.tr('insights.bool_on')
            : context.tr('insights.bool_off');
      case 'reading_speed':
      case 'text_scale':
        final d = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
        return '${d.toStringAsFixed(2)}×';
      case 'volume':
        final d = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
        return '${(d * 100).round()}%';
    }
    return v.toString();
  }
}

/* "Now → Suggested" shown side by side with an arrow, so the change is
   clear. */
class _ValueComparison extends StatelessWidget {
  final String currentLabel;
  final String suggestedLabel;
  final String? current;
  final String suggested;
  final Color tint;
  const _ValueComparison({
    required this.currentLabel,
    required this.suggestedLabel,
    required this.current,
    required this.suggested,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _ValueBox(
            label: currentLabel,
            value: current ?? '—',
            background: AppColors.surface,
            faded: true,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward_rounded,
              size: 18, color: AppColors.textSecondary),
        ),
        Expanded(
          child: _ValueBox(
            label: suggestedLabel,
            value: suggested,
            background: tint,
            faded: false,
          ),
        ),
      ],
    );
  }
}

class _ValueBox extends StatelessWidget {
  final String label;
  final String value;
  final Color background;
  final bool faded;
  const _ValueBox({
    required this.label,
    required this.value,
    required this.background,
    required this.faded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w800,
              color: faded
                  ? AppColors.textSecondary
                  : AppColors.textPrimary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontWeight: faded ? FontWeight.w700 : FontWeight.w800,
                fontSize: 15,
                color: faded ? AppColors.textSecondary : AppColors.textPrimary,
                decoration:
                    faded ? TextDecoration.lineThrough : TextDecoration.none,
                decorationColor: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* Callout with a soft tint, lightbulb, and left stripe — makes the reason
   feel like a friendly note. */
class _ReasonCallout extends StatelessWidget {
  final String text;
  const _ReasonCallout({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.softMint.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          left: BorderSide(color: AppColors.success, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline_rounded,
              size: 16, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* Accept / Edit & accept / Dismiss row. Accept stands out most, Dismiss
   the least. */
class _ActionBar extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onEditAccept;
  final VoidCallback onDismiss;
  const _ActionBar({
    required this.onAccept,
    required this.onEditAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: onAccept,
          icon: const Icon(Icons.check_rounded, size: 16),
          label: Text(context.tr('insights.accept')),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onEditAccept,
          icon: const Icon(Icons.tune_rounded, size: 16),
          label: Text(context.tr('insights.edit_accept')),
          style: OutlinedButton.styleFrom(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          ),
        ),
        TextButton.icon(
          onPressed: onDismiss,
          icon: const Icon(Icons.close_rounded, size: 16),
          label: Text(context.tr('insights.dismiss')),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/* Coloured pill with an icon shown on a resolved tip, so accepted vs.
   dismissed is clear at a glance. */
class _StatusBadge extends StatelessWidget {
  final AiSuggestionItem item;
  const _StatusBadge({required this.item});

  @override
  Widget build(BuildContext context) {
    final accepted = item.isAccepted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accepted ? AppColors.iconCircleGreen : AppColors.softLavender,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            accepted ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 13,
            color: accepted ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            accepted
                ? context.tr('insights.applied_badge')
                : context.tr('insights.dismissed_badge'),
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11,
                color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/* Dialog from the "Edit & accept" button. The control fits the setting:
   slider for numbers, dropdown for the voice, switch for on/off. */
class _EditValueDialog extends StatefulWidget {
  final AiSuggestionItem item;
  const _EditValueDialog({required this.item});

  @override
  State<_EditValueDialog> createState() => _EditValueDialogState();
}

class _EditValueDialogState extends State<_EditValueDialog> {
  late dynamic _value;

  @override
  void initState() {
    super.initState();
    _value = widget.item.suggestedValue;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('insights.edit_value_title')),
      content: SizedBox(
        width: double.maxFinite,
        child: _buildEditor(context),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(context.tr('insights.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_value),
          child: Text(context.tr('insights.save')),
        ),
      ],
    );
  }

  Widget _buildEditor(BuildContext context) {
    switch (widget.item.settingKey) {
      case 'reading_speed':
        return _slider(0.5, 2.0, 0.05);
      case 'volume':
        return _slider(0.0, 1.0, 0.05);
      case 'text_scale':
        return _slider(0.7, 2.0, 0.05);
      case 'narrator_voice':
        const voices = [
          'calm_female',
          'gentle_female',
          'warm_male',
          'friendly_child',
          'soothing_elder',
        ];
        final current = voices.contains(_value as String?)
            ? _value as String
            : voices.first;
        return DropdownButtonFormField<String>(
          initialValue: current,
          items: [
            for (final v in voices)
              DropdownMenuItem(value: v, child: Text(context.tr('voice.$v'))),
          ],
          onChanged: (v) => setState(() => _value = v),
        );
      case 'reduced_animations':
      case 'auto_play_next':
      case 'read_along':
        final on =
            _value == true || _value == 'true' || _value == 1;
        return SwitchListTile(
          value: on,
          onChanged: (v) => setState(() => _value = v),
          title: Text(on
              ? context.tr('insights.bool_on')
              : context.tr('insights.bool_off')),
        );
    }
    return Text(_value.toString());
  }

  Widget _slider(double min, double max, double step) {
    final asNum = _value is num
        ? (_value as num).toDouble()
        : double.tryParse(_value.toString()) ?? min;
    final clamped = asNum.clamp(min, max).toDouble();
    final divisions = ((max - min) / step).round();
    final label = widget.item.settingKey == 'volume'
        ? '${(clamped * 100).round()}%'
        : '${clamped.toStringAsFixed(2)}×';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        Slider(
          value: clamped,
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          onChanged: (v) => setState(() {
            // Snap to the step so the saved value passes the backend check.
            _value = (v / step).round() * step;
          }),
        ),
      ],
    );
  }
}
