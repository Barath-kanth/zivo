import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/data/models/task_status.dart';

/// A small colored pill badge displaying the task's current status.
class TaskStatusBadge extends StatelessWidget {
  const TaskStatusBadge({super.key, required this.status});
  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: status.color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: status.color,
              shape: BoxShape.circle,
            ),
          ),
          const Gap(5),
          Text(
            status.displayLabel,
            style: AppTextStyles.bodySmall.copyWith(
              color: status.color,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
