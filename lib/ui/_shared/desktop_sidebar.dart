import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyperlocal/blocs/a11y/a11y_cubit.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/ui/_shared/a11y_hub.dart';
import 'package:hyperlocal/ui/_shared/a11y_landmarks.dart';
import 'package:hyperlocal/ui/_shared/mode_switch_card.dart';
import 'zivo_logo.dart';

class AppNavDestination {
  const AppNavDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Desktop destinations reuse the same guarded callbacks as the mobile dock.
class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    super.key,
    required this.isHelper,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    this.screenHint = 'Zivo desktop screen',
  });
  final bool isHelper;
  final int selectedIndex;
  final List<AppNavDestination> destinations;
  final ValueChanged<int> onDestinationSelected;
  final String screenHint;

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    return SizedBox(
      width: 216,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.canvas,
          border: Border(right: BorderSide(color: palette.border)),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 30, 24, 20),
                child: ZivoLogo(size: 42, showWordmark: true),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: A11yHeading(
                  text: isHelper ? 'Helper workspace' : 'Your workspace',
                  level: 2,
                  style: AppTextStyles.capsLabel.copyWith(
                    fontSize: 10,
                    color: palette.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (var i = 0; i < destinations.length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      _NavTile(
                        item: destinations[i],
                        selected: selectedIndex == i,
                        onTap: () => onDestinationSelected(i),
                      ),
                    ],
                  ],
                ),
              ),
              // Helper/Client switch sits above Accessibility (screenshot 2).
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: ModeSwitchCard(compact: true),
              ),
              Divider(indent: 24, endIndent: 24, color: palette.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: BlocBuilder<A11yCubit, bool>(
                  builder: (context, on) {
                    return Material(
                      color: on
                          ? palette.accent.withValues(alpha: 0.16)
                          : palette.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => showA11yHub(
                          context,
                          screenHint: screenHint,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.accessibility_new_rounded,
                                size: 20,
                                color: on
                                    ? palette.accent
                                    : palette.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  on
                                      ? context
                                          .watch<LocaleCubit>()
                                          .t('a11y.modeOn')
                                      : context
                                          .watch<LocaleCubit>()
                                          .t('nav.accessibility'),
                                  style: AppTextStyles.bodySmall.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: palette.textPrimary,
                                  ),
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  size: 18, color: palette.textMuted),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppNavDestination item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: Material(
        color: selected ? palette.helperSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  selected ? item.activeIcon : item.icon,
                  size: 23,
                  color: selected
                      ? palette.accent
                      : palette.textSecondary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? palette.accent
                          : palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
