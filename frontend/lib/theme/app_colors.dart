import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color background = Color(0xFFEEF2F6);
  static const Color surface = Colors.white;
  static const Color cardBorder = Color(0xFFE3E8EE);

  /* Text is kept dark: the old light greys looked blurry on the pale
     backgrounds. Secondary and muted text still read clearly (contrast
     about 7:1 and 4.5:1 on white). */
  static const Color textPrimary = Color(0xFF1A202C);
  static const Color textSecondary = Color(0xFF4A5568);
  static const Color textMuted = Color(0xFF718096);

  static const Color primaryBlue = Color(0xFFAFC4DC);
  // Links, icons and filled buttons with white text: dark enough to read.
  static const Color primaryBlueDark = Color(0xFF5B7FA6);
  static const Color softLavender = Color(0xFFD9C8E8);
  static const Color softMint = Color(0xFFC8E4D2);
  static const Color softMintDark = Color(0xFFA8D5BA);
  static const Color softPeach = Color(0xFFF5E3D0);
  static const Color softPink = Color(0xFFF5D5DD);
  static const Color softYellow = Color(0xFFFDE9B8);

  static const Color moodHappy = Color(0xFFC8E4D2);
  static const Color moodCalm = Color(0xFFAFC4DC);
  static const Color moodCurious = Color(0xFFF5E3D0);
  static const Color moodSleepy = Color(0xFFD9C8E8);

  static const Color iconCircleBlue = Color(0xFFDDE7F2);
  static const Color iconCircleGreen = Color(0xFFD6ECDE);
  static const Color iconCirclePeach = Color(0xFFF1E3D3);
  static const Color iconCirclePurple = Color(0xFFE6DCEE);

  static const Color success = Color(0xFF6FBF73);
  static const Color warning = Color(0xFFE8A87C);
  static const Color danger = Color(0xFFE07A7A);
}
