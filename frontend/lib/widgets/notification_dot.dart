import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/* A small red dot that marks a tab with something new, such as a friend
   request or an answer to one. */
class NotificationDot extends StatelessWidget {
  const NotificationDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: AppColors.danger,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface, width: 1.5),
      ),
    );
  }
}
