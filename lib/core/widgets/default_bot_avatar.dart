import 'package:flutter/material.dart';

/// The homepage's bot mark, scaled consistently for profile images.
class DefaultBotAvatar extends StatelessWidget {
  const DefaultBotAvatar({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(size * 20 / 64),
      ),
      child: Icon(
        Icons.smart_toy_rounded,
        size: size / 2,
        color: colors.onPrimaryContainer,
      ),
    );
  }
}
