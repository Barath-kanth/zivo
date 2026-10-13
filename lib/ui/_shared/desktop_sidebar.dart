import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyperlocal/blocs/a11y/a11y_cubit.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/ui/_shared/a11y_hub.dart';
import 'package:hyperlocal/ui/shell/mode_toggle_widget.dart';
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
  Widget build(BuildContext context) => SizedBox(
        width: 216,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: AppColors.borderColor)),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 30, 24, 28),
                  child: ZivoLogo(size: 42, showWordmark: true),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    isHelper ? 'HELPER WORKSPACE' : 'YOUR WORKSPACE',
                    style: AppTextStyles.capsLabel.copyWith(fontSize: 10),
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
                const Divider(indent: 24, endIndent: 24),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: BlocBuilder<A11yCubit, bool>(
                    builder: (context, on) {
                      return Material(
                        color: on
                            ? AppColors.helperAccent.withValues(alpha: 0.12)
                            : const Color(0xFFF6F6F6),
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
                                      ? AppColors.helperAccent
                                      : AppColors.textMuted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    on ? 'Accessibility on' : 'Accessibility',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.chevron_right, size: 18),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Row(
                    children: [
                      ModeToggleWidget(isHelper: isHelper),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isHelper
                              ? 'Switch to\nClient mode'
                              : 'Switch to\nHelper mode',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
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
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: Material(
        color: selected ? AppColors.accent : Colors.transparent,
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
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? Colors.white : AppColors.textSecondary,
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
