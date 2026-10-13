import 'package:flutter/material.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/ui/shell/mode_toggle_widget.dart';
import 'zivo_logo.dart';

class AppNavDestination {
  const AppNavDestination({required this.icon, required this.activeIcon,
    required this.label});
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Desktop destinations reuse the same guarded callbacks as the mobile dock.
class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({super.key, required this.isHelper,
    required this.selectedIndex, required this.destinations,
    required this.onDestinationSelected});
  final bool isHelper;
  final int selectedIndex;
  final List<AppNavDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

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
              child: Text(isHelper ? 'HELPER WORKSPACE' : 'YOUR WORKSPACE',
                style: AppTextStyles.capsLabel.copyWith(fontSize: 10)),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: destinations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final item = destinations[index];
                  final selected = selectedIndex == index;
                  return Semantics(
                    selected: selected,
                    child: ListTile(
                      selected: selected,
                      selectedTileColor: AppColors.accent,
                      selectedColor: Colors.white,
                      textColor: AppColors.textSecondary,
                      iconColor: AppColors.textSecondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Icon(selected ? item.activeIcon : item.icon, size: 23),
                      title: Text(item.label,
                        style: TextStyle(fontSize: 14,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                      onTap: () => onDestinationSelected(index),
                    ),
                  );
                },
              ),
            ),
            const Divider(indent: 24, endIndent: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Row(
                children: [
                  ModeToggleWidget(isHelper: isHelper),
                  const SizedBox(width: 12),
                  Expanded(child: Text(
                    isHelper ? 'Switch to\nClient mode' : 'Switch to\nHelper mode',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary, height: 1.5),
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
