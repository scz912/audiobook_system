import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/community/contact_settings.dart';
import '../theme/app_colors.dart';

// The solid colours offered for a chat background.
const chatBackgroundColors = <String>[
  '#EEF2F6', '#DDE7F2', '#AFC4DC', '#C8E4D2', '#A8D5BA', '#FDE9B8',
  '#F5E3D0', '#F5D5DD', '#F2B3CB', '#D9C8E8', '#C9B6EC', '#9ED8DB',
  '#FFFFFF', '#FFF7E6', '#E8F5E9', '#2D3748', '#3B4A6B', '#1F3B4D',
];

// The gradients offered, by the name the server stores.
const chatBackgroundGradients = <String, List<Color>>{
  'sunrise': [Color(0xFFFDE9B8), Color(0xFFF5BE96), Color(0xFFF2B3CB)],
  'ocean': [Color(0xFFDDE7F2), Color(0xFFA9C5E8), Color(0xFF7C9EC0)],
  'meadow': [Color(0xFFE8F5E9), Color(0xFFC8E4D2), Color(0xFFA8D5BA)],
  'lavender': [Color(0xFFF3EEFA), Color(0xFFD9C8E8), Color(0xFFC9B6EC)],
  'peach': [Color(0xFFFFF3E6), Color(0xFFF5E3D0), Color(0xFFF5BE96)],
  'mint': [Color(0xFFE6F7F6), Color(0xFF9ED8DB), Color(0xFF6FBFC2)],
  'candy': [Color(0xFFF5D5DD), Color(0xFFD9C8E8), Color(0xFFA9C5E8)],
  'dusk': [Color(0xFF3B4A6B), Color(0xFF6B5B95), Color(0xFFC9B6EC)],
  'night': [Color(0xFF1F2937), Color(0xFF2D3748), Color(0xFF3B4A6B)],
};

Color parseHexColor(String hex, [Color fallback = AppColors.background]) {
  final clean = hex.replaceFirst('#', '');
  final value = int.tryParse(clean, radix: 16);
  if (value == null || clean.length != 6) return fallback;
  return Color(0xFF000000 | value);
}

/* Whether text and bubbles drawn on this background need to be light. Dark
   colours, the dark gradients and pictures (which vary) get the help. */
bool chatBackgroundIsDark(ChatBackground bg) {
  switch (bg.type) {
    case 'color':
      return parseHexColor(bg.value!).computeLuminance() < 0.3;
    case 'gradient':
      final colors = chatBackgroundGradients[bg.value];
      return colors != null && colors.first.computeLuminance() < 0.3;
    case 'image':
      return true;
    default:
      return false;
  }
}

/* Paints [background] behind [child]. A picture is dimmed slightly so
   chat bubbles stay readable on top of it. */
class ChatBackgroundView extends StatelessWidget {
  final ChatBackground background;
  final Widget child;
  final BorderRadius? borderRadius;
  const ChatBackgroundView({
    super.key,
    required this.background,
    required this.child,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final bg = background;
    Widget layer;
    if (bg.isNone) {
      layer = const ColoredBox(color: AppColors.background);
    } else if (bg.type == 'color') {
      layer = ColoredBox(color: parseHexColor(bg.value!));
    } else if (bg.type == 'gradient') {
      final colors = chatBackgroundGradients[bg.value] ??
          const [AppColors.background, AppColors.background];
      layer = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
      );
    } else if (bg.type == 'image') {
      layer = Stack(
        fit: StackFit.expand,
        children: [
          // A picture just picked from the phone is a file path until
          // it's uploaded; after that it's a URL.
          if (bg.value!.startsWith('http'))
            CachedNetworkImage(
              imageUrl: bg.value!,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) =>
                  const ColoredBox(color: AppColors.background),
            )
          else
            Image.file(File(bg.value!), fit: BoxFit.cover),
          ColoredBox(color: Colors.black.withValues(alpha: 0.12)),
        ],
      );
    } else {
      layer = const ColoredBox(color: AppColors.background);
    }

    final stack = Stack(
      fit: StackFit.expand,
      children: [Positioned.fill(child: layer), child],
    );
    return borderRadius == null
        ? stack
        : ClipRRect(borderRadius: borderRadius!, child: stack);
  }
}
