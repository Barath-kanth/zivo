import 'package:flutter/material.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/data/models/task.dart';

/// Presentation-only icons. Task category identifiers stay unchanged.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon(this.category,
      {super.key, this.size = 28, this.color = AppColors.textPrimary});

  final TaskCategory category;
  final double size;
  final Color color;

  /// CC0 [3dicons.co](https://3dicons.co/) iso-color PNGs (transparent, no plate).
  static String assetPathFor(TaskCategory category) {
    switch (category) {
      case TaskCategory.queueStanding:
        return 'assets/icons/3d/clock.png';
      case TaskCategory.laundry:
        return 'assets/icons/3d/scissor.png';
      case TaskCategory.groceryRun:
        return 'assets/icons/3d/bag.png';
      case TaskCategory.homeCleaning:
        return 'assets/icons/3d/bucket.png';
      case TaskCategory.homeCooking:
        return 'assets/icons/3d/tea-cup.png';
      case TaskCategory.movingHelp:
        return 'assets/icons/3d/box.png';
      case TaskCategory.tutoring:
        return 'assets/icons/3d/book.png';
      case TaskCategory.techHelp:
        return 'assets/icons/3d/computer.png';
      case TaskCategory.petCare:
        return 'assets/icons/3d/heart.png';
      case TaskCategory.tailoring:
        return 'assets/icons/3d/paint-brush.png';
      case TaskCategory.driver:
        return 'assets/icons/3d/scooter.png';
      case TaskCategory.errandRun:
        return 'assets/icons/3d/map-pin.png';
      case TaskCategory.gardening:
        return 'assets/icons/3d/flower.png';
      case TaskCategory.documentWork:
        return 'assets/icons/3d/copy.png';
      case TaskCategory.hospitalCompanion:
        return 'assets/icons/3d/lab.png';
      case TaskCategory.babysitting:
        return 'assets/icons/3d/boy.png';
      case TaskCategory.elderCare:
        return 'assets/icons/3d/chat.png';
      case TaskCategory.eventHelp:
        return 'assets/icons/3d/calender.png';
      case TaskCategory.photography:
        return 'assets/icons/3d/camera.png';
      case TaskCategory.homeRepair:
        return 'assets/icons/3d/tool.png';
      case TaskCategory.other:
        return 'assets/icons/3d/target.png';
    }
  }

  static const moreAssetPath = 'assets/icons/3d/setting.png';

  /// Seven services plus More create two balanced rows on phones.
  static const mobilePrimary = <TaskCategory>[
    TaskCategory.groceryRun,
    TaskCategory.homeCleaning,
    TaskCategory.laundry,
    TaskCategory.errandRun,
    TaskCategory.driver,
    TaskCategory.movingHelp,
    TaskCategory.techHelp,
  ];

  static List<TaskCategory> get mobileOverflow => TaskCategory.values
      .where((c) => !mobilePrimary.contains(c))
      .toList(growable: false);

  static IconData iconFor(TaskCategory category) {
    switch (category) {
      case TaskCategory.queueStanding:
        return Icons.groups_rounded;
      case TaskCategory.laundry:
        return Icons.local_laundry_service_rounded;
      case TaskCategory.groceryRun:
        return Icons.shopping_bag_rounded;
      case TaskCategory.homeCleaning:
        return Icons.cleaning_services_rounded;
      case TaskCategory.homeCooking:
        return Icons.restaurant_rounded;
      case TaskCategory.movingHelp:
        return Icons.inventory_2_rounded;
      case TaskCategory.tutoring:
        return Icons.school_rounded;
      case TaskCategory.techHelp:
        return Icons.devices_rounded;
      case TaskCategory.petCare:
        return Icons.pets_rounded;
      case TaskCategory.tailoring:
        return Icons.checkroom_rounded;
      case TaskCategory.driver:
        return Icons.directions_car_rounded;
      case TaskCategory.errandRun:
        return Icons.directions_walk_rounded;
      case TaskCategory.gardening:
        return Icons.yard_rounded;
      case TaskCategory.documentWork:
        return Icons.description_rounded;
      case TaskCategory.hospitalCompanion:
        return Icons.local_hospital_rounded;
      case TaskCategory.babysitting:
        return Icons.child_care_rounded;
      case TaskCategory.elderCare:
        return Icons.elderly_rounded;
      case TaskCategory.eventHelp:
        return Icons.celebration_rounded;
      case TaskCategory.photography:
        return Icons.photo_camera_rounded;
      case TaskCategory.homeRepair:
        return Icons.handyman_rounded;
      case TaskCategory.other:
        return Icons.apps_rounded;
    }
  }

  static bool usesSymbol(TaskCategory category) => const {
    TaskCategory.laundry, TaskCategory.tailoring, TaskCategory.homeCooking,
    TaskCategory.petCare, TaskCategory.elderCare, TaskCategory.driver,
  }.contains(category);

  static Color accentFor(TaskCategory category) {
    switch (category) {
      case TaskCategory.groceryRun:
      case TaskCategory.gardening:
      case TaskCategory.errandRun:
        return AppColors.brandGreen;
      case TaskCategory.homeCooking:
      case TaskCategory.movingHelp:
      case TaskCategory.homeRepair:
        return const Color(0xFFE67E22);
      case TaskCategory.driver:
      case TaskCategory.techHelp:
      case TaskCategory.queueStanding:
        return const Color(0xFF2F80ED);
      case TaskCategory.hospitalCompanion:
        return const Color(0xFFE74C3C);
      case TaskCategory.tutoring:
      case TaskCategory.elderCare:
        return const Color(0xFF8E44AD);
      default:
        return const Color(0xFF2C3E50);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (usesSymbol(category)) {
      return Icon(iconFor(category), size: size, color: accentFor(category));
    }
    return Image.asset(
      assetPathFor(category),
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) =>
          Icon(iconFor(category), size: size, color: color),
    );
  }
}

/// Real 3dicons render only — no plate, gradient, or shadow backdrop.
class CategoryIconBadge extends StatelessWidget {
  const CategoryIconBadge(this.category, {super.key, this.size = 56});
  final TaskCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CategoryIcon.usesSymbol(category)
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: CategoryIcon.accentFor(category).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(CategoryIcon.iconFor(category), size: size * 0.66,
                color: CategoryIcon.accentFor(category)),
            )
          : Image.asset(
        CategoryIcon.assetPathFor(category),
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => Icon(
          CategoryIcon.iconFor(category),
          size: size * 0.7,
          color: CategoryIcon.accentFor(category),
        ),
      ),
    );
  }
}

/// "More" tile icon (settings cube from 3dicons).
class MoreIconBadge extends StatelessWidget {
  const MoreIconBadge({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        CategoryIcon.moreAssetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => Icon(
          Icons.apps_rounded,
          size: size * 0.7,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
