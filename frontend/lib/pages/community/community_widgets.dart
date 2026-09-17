import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

// Turn a "#RRGGBB" string into a Color, falling back to a soft blue.
Color communityColor(String? hex) {
  if (hex == null || hex.isEmpty) return AppColors.iconCircleBlue;
  var value = hex.replaceAll('#', '');
  if (value.length == 6) value = 'FF$value';
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? AppColors.iconCircleBlue : Color(parsed);
}

// A round avatar showing the member's emoji on their chosen colour.
class MemberAvatar extends StatelessWidget {
  final String emoji;
  final String? colorHex;
  final double size;

  const MemberAvatar({
    super.key,
    required this.emoji,
    this.colorHex,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: communityColor(colorHex),
        shape: BoxShape.circle,
      ),
      child: Text(
        emoji.isEmpty ? '🙂' : emoji,
        style: TextStyle(fontSize: size * 0.5),
      ),
    );
  }
}

// A small red badge with a count, for unread chats / pending requests.
class CountBadge extends StatelessWidget {
  final int count;
  const CountBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(10),
      ),
      constraints: const BoxConstraints(minWidth: 18),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// Short "5m", "3h", "2d" style relative time for chat and feed timestamps.
String shortAgo(DateTime? when) {
  if (when == null) return '';
  final diff = DateTime.now().difference(when);
  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${when.day}/${when.month}';
}

// Exact clock time like "9:05 PM". Adds the date if it's not today.
String exactTime(DateTime? when) {
  if (when == null) return '';
  final local = when.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  final time = '$hour12:$minute $period';

  final now = DateTime.now();
  final sameDay =
      local.year == now.year && local.month == now.month && local.day == now.day;
  if (sameDay) return time;
  return '${local.day}/${local.month} $time';
}
