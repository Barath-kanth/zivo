import 'package:flutter/material.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/ui/_shared/zivo_logo.dart';

/// ZePay-style cover hero for Client / Helper home.
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

  String get _asset => isHelper
      ? 'assets/images/zivo_helper_cover.jpg'
      : 'assets/images/zivo_client_cover.jpg';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                _asset,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => Container(
                  color: isHelper
                      ? AppColors.brandGreenSoft
                      : AppColors.surfaceDark,
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      const ZivoLogo(
                        size: 34,
                        showWordmark: true,
                        markOnDark: true,
                        wordmarkColor: Colors.white,
                      ),
                      const Spacer(),
                      if (onModeTap != null)
                        Material(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(22),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(22),
                            onTap: onModeTap,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isHelper
                                        ? Icons.handshake_rounded
                                        : Icons.person_search_rounded,
                                    size: 16,
                                    color: Colors.black,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isHelper ? 'Helper mode' : 'Client mode',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(
                                    Icons.swap_horiz_rounded,
                                    size: 16,
                                    color: Colors.black54,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (trailing != null) ...[
                        const SizedBox(width: 8),
                        trailing!,
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 28,
                child: Text(
                  isHelper
                      ? 'Earn nearby — pick jobs that fit you'
                      : 'Get help nearby — queues, chores, care',
                  style: AppTextStyles.headingMedium.copyWith(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    shadows: const [
                      Shadow(blurRadius: 12, color: Colors.black54),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (onSearchTap != null)
          Transform.translate(
            offset: const Offset(0, -18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: Colors.white,
                elevation: 6,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: onSearchTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded,
                            color: AppColors.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            searchHint ??
                                (isHelper
                                    ? 'Search jobs near you'
                                    : 'Find services, chores & help'),
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
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
}
