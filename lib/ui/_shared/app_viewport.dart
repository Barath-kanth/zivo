import 'package:flutter/material.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';

/// Shared horizontal page gutter — keep chips/cards inside this inset.
const double kPageGutter = 16;

/// A bounded reading surface on desktop, edge to edge on phones.
/// Gutter color follows theme so dark mode never shows white/mint sides.
class AppViewport extends StatelessWidget {
  const AppViewport({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    return ColoredBox(
      color: palette.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: SizedBox.expand(
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}
