import 'package:flutter/material.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/data/models/task.dart';

/// Presentation-only icons. Task category identifiers stay unchanged.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon(this.category, {super.key, this.size = 28,
    this.color = AppColors.textPrimary});

  final TaskCategory category;
  final double size;
  final Color color;

  static IconData iconFor(TaskCategory category) {
    switch (category) {
      case TaskCategory.queueStanding: return Icons.people_outline;
      case TaskCategory.laundry: return Icons.local_laundry_service_outlined;
      case TaskCategory.groceryRun: return Icons.shopping_bag_outlined;
      case TaskCategory.homeCleaning: return Icons.cleaning_services_outlined;
      case TaskCategory.homeCooking: return Icons.restaurant_outlined;
      case TaskCategory.movingHelp: return Icons.inventory_2_outlined;
      case TaskCategory.tutoring: return Icons.school_outlined;
      case TaskCategory.techHelp: return Icons.devices_outlined;
      case TaskCategory.petCare: return Icons.pets_outlined;
      case TaskCategory.tailoring: return Icons.checkroom_outlined;
      case TaskCategory.driver: return Icons.directions_car_outlined;
      case TaskCategory.errandRun: return Icons.directions_walk_outlined;
      case TaskCategory.gardening: return Icons.yard_outlined;
      case TaskCategory.documentWork: return Icons.description_outlined;
      case TaskCategory.hospitalCompanion: return Icons.local_hospital_outlined;
      case TaskCategory.babysitting: return Icons.child_care_outlined;
      case TaskCategory.elderCare: return Icons.elderly_outlined;
      case TaskCategory.eventHelp: return Icons.celebration_outlined;
      case TaskCategory.photography: return Icons.photo_camera_outlined;
      case TaskCategory.homeRepair: return Icons.handyman_outlined;
      case TaskCategory.other: return Icons.more_horiz;
    }
  }

  @override
  Widget build(BuildContext context) => Icon(iconFor(category),
    size: size, color: color);
}

/// Consistent service pictogram treatment across browsing and task creation.
/// The icon remains a vector glyph, with no downloaded bitmap assets.
class CategoryIconBadge extends StatelessWidget {
  const CategoryIconBadge(this.category, {super.key, this.size = 52});
  final TaskCategory category;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(size * 0.28),
      border: Border.all(color: AppColors.borderColor),
    ),
    child: Center(child: CategoryIcon(category, size: size * 0.54)),
  );
}
