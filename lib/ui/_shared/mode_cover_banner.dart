import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';

import 'a11y_landmarks.dart';
import 'neighbourhood_art.dart';
import 'zivo_logo.dart';

/// Compact reference-inspired home header shared by both app roles.
class ModeCoverBanner extends StatelessWidget {
  const ModeCoverBanner({
    super.key,
    required this.isHelper,
    this.onModeTap,
    this.trailing,
    this.searchHint,
    this.onSearchTap,
    this.height = 200,
  });
  final bool isHelper;
  final VoidCallback? onModeTap;
  final Widget? trailing;
  final String? searchHint;
  final VoidCallback? onSearchTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final palette = ZivoPalette.of(context);
    final tagline =
        isHelper ? l.t('home.helperTagline') : l.t('home.tagline');
    return A11yLandmark.region(
      label: isHelper ? 'Helper home header' : 'Client home header',
      child: Column(
      children: [
        ColoredBox(
          color: palette.coverTint,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      // Wordmark auto-flips white on dark / black on light.
                      child: ZivoLogo(size: 32, showWordmark: true),
                    ),
                  ),
                  if (onModeTap != null) ...[
                    if (MediaQuery.sizeOf(context).width < 360 ||
                        MediaQuery.textScalerOf(context).scale(14) > 20)
                      IconButton(
                        tooltip: isHelper
                            ? l.t('nav.switchClient')
                            : l.t('nav.switchHelper'),
                        onPressed: onModeTap,
                        icon: const Icon(Icons.swap_horiz_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: palette.card,
                          foregroundColor: palette.textPrimary,
                        ),
                      )
                    else
                      TextButton.icon(
                        onPressed: onModeTap,
                        style: TextButton.styleFrom(
                          backgroundColor: palette.card.withValues(alpha: .85),
                          foregroundColor: palette.textPrimary,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(48, 44),
                        ),
                        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                        label: Text(
                          isHelper ? l.t('home.helper') : l.t('home.client'),
                        ),
                      ),
                    if (trailing != null) const SizedBox(width: 8),
                  ],
                  if (trailing != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: trailing!,
                    ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          height: height - 48,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Always the original light neighbourhood art (readable cover).
              NeighbourhoodArt(helper: isHelper),
              Positioned(
                left: 16,
                right: 16,
                top: 10,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // Soft pill so dark-theme users still read tagline on light art.
                      color: const Color(0xF2FFFFFF),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: A11yHeading(
                        text: tagline,
                        level: 1,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.headingMedium.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: -0.3,
                          height: 1.25,
                          color: const Color(0xFF0A0A0A),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (onSearchTap != null)
          Transform.translate(
            offset: const Offset(0, -16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Semantics(
                button: true,
                label: searchHint ?? l.t('home.searchHint'),
                child: Material(
                  color: palette.card,
                  elevation: 2,
                  shadowColor: const Color(0x14000000),
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onSearchTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: palette.textPrimary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              searchHint ?? l.t('home.searchHint'),
                              style: AppTextStyles.bodySmall.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: palette.textSecondary,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: palette.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
    );
  }
}
