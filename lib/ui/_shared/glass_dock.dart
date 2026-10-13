import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';

/// A clipped, single-pass frosted surface. No animated blur or external assets.
/// High-contrast mode uses an opaque surface for predictable legibility.
class GlassDock extends StatelessWidget {
  const GlassDock({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final opaque = MediaQuery.highContrastOf(context);
    final radius = BorderRadius.circular(30);
    // BoxDecoration ignores color when a gradient is present. Paint the
    // white scrim separately so dark content cannot obscure the nav labels.
    final surface = ColoredBox(
      key: const ValueKey('glass-dock-scrim'),
      color: opaque ? Colors.white : AppColors.glassSurface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: opaque ? AppColors.borderColor
                : Colors.white.withValues(alpha: 0.9),
            width: 1,
          ),
          gradient: opaque ? null : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x40FFFFFF), Color(0x08FFFFFF)],
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
              boxShadow: const [
                BoxShadow(color: Color(0x14000000), blurRadius: 28,
                    offset: Offset(0, 8)),
                BoxShadow(color: Color(0x08000000), blurRadius: 4,
                    offset: Offset(0, 1)),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: opaque ? surface : BackdropFilter(
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
