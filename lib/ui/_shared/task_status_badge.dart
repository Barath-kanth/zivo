import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/data/models/task_status.dart';

/// A small colored pill badge displaying the task's current status.
class TaskStatusBadge extends StatelessWidget {
  const TaskStatusBadge({super.key, required this.status});
  final TaskStatus status;

  static String labelKey(TaskStatus status) {
    switch (status) {
      case TaskStatus.open:
        return 'status.open';
      case TaskStatus.matched:
        return 'status.matched';
      case TaskStatus.inProgress:
        return 'status.inProgress';
      case TaskStatus.completed:
        return 'status.completed';
      case TaskStatus.cancelled:
        return 'status.cancelled';
      case TaskStatus.disputed:
        return 'status.disputed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = context.watch<LocaleCubit>().t(labelKey(status));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: status.color.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.bodySmall.copyWith(
          color: status.color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
          height: 1.1,
        ),
      ),
    );
  }
}
