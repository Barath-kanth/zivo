import 'package:flutter/material.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';

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
  Widget build(BuildContext context) => Column(
    children: [
      ColoredBox(
        color: const Color(0xFFE7F5FC),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                const ZivoLogo(size: 32, showWordmark: true),
                const Spacer(),
                if (onModeTap != null &&
                    (MediaQuery.sizeOf(context).width < 360 ||
                        MediaQuery.textScalerOf(context).scale(14) > 20))
                  IconButton(
                    tooltip: isHelper
                        ? 'Switch to client mode'
                        : 'Switch to helper mode',
                    onPressed: onModeTap,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    style: IconButton.styleFrom(backgroundColor: Colors.white),
                  )
                else if (onModeTap != null)
                  TextButton.icon(
                    onPressed: onModeTap,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: .85),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(48, 44),
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: Text(isHelper ? 'Helper' : 'Client'),
                  ),
                if (trailing != null) ...[const SizedBox(width: 10), trailing!],
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
            NeighbourhoodArt(helper: isHelper),
            Positioned(
              left: 20,
              right: 20,
              top: 10,
              child: Text(
                isHelper
                    ? 'Good work. Close to home.'
                    : 'A little help. A better day.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.headingMedium.copyWith(
                  fontWeight: FontWeight.w700,
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
            child: Material(
              color: Colors.white,
              elevation: 2,
              shadowColor: const Color(0x14000000),
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onSearchTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 17,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: AppColors.textPrimary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          searchHint ?? 'Search nearby',
                          style: AppTextStyles.bodyMedium,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
