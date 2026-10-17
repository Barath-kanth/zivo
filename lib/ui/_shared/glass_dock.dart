import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';

/// A clipped, single-pass frosted surface. No animated blur or external assets.
/// High-contrast mode uses an opaque surface for predictable legibility.
class GlassDock extends StatelessWidget {
  const GlassDock({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final opaque = MediaQuery.highContrastOf(context);
    final palette = ZivoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(30);
    // BoxDecoration ignores color when a gradient is present. Paint the
    // scrim separately so dark content cannot obscure the nav labels.
    final surface = ColoredBox(
      key: const ValueKey('glass-dock-scrim'),
      color: opaque ? palette.card : palette.glass,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: opaque
                ? palette.border
                : (isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.9)),
            width: 1,
          ),
          gradient: opaque
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          Colors.white.withValues(alpha: 0.08),
                          Colors.white.withValues(alpha: 0.02),
                        ]
                      : const [Color(0x40FFFFFF), Color(0x08FFFFFF)],
                ),
        ),
        child: Padding(padding: const EdgeInsets.all(8), child: child),
      ),
    );

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Align(
        heightFactor: 1,
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                  blurRadius: 28,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: opaque
                  ? surface
                  : BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: surface,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
