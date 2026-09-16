import 'package:flutter/material.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';

/// Maps to the Postgres `task_status` enum.
enum TaskStatus {
  open,
  matched,
  inProgress,
  completed,
  cancelled,
  disputed;

  String get dbValue {
    switch (this) {
      case TaskStatus.open:        return 'open';
      case TaskStatus.matched:     return 'matched';
      case TaskStatus.inProgress:  return 'in_progress';
      case TaskStatus.completed:   return 'completed';
      case TaskStatus.cancelled:   return 'cancelled';
      case TaskStatus.disputed:    return 'disputed';
    }
  }

  String get displayLabel {
    switch (this) {
      case TaskStatus.open:        return 'Open';
      case TaskStatus.matched:     return 'Matched';
      case TaskStatus.inProgress:  return 'In Progress';
      case TaskStatus.completed:   return 'Completed';
      case TaskStatus.cancelled:   return 'Cancelled';
      case TaskStatus.disputed:    return 'Disputed';
    }
  }

  Color get color {
    switch (this) {
      case TaskStatus.open:        return AppColors.statusOpen;
      case TaskStatus.matched:     return AppColors.statusMatched;
      case TaskStatus.inProgress:  return AppColors.statusInProgress;
      case TaskStatus.completed:   return AppColors.statusCompleted;
      case TaskStatus.cancelled:   return AppColors.errorColor;
      case TaskStatus.disputed:    return AppColors.warningColor;
    }
  }

  static TaskStatus fromString(String value) {
    switch (value) {
      case 'open':        return TaskStatus.open;
      case 'matched':     return TaskStatus.matched;
      case 'in_progress': return TaskStatus.inProgress;
      case 'completed':   return TaskStatus.completed;
      case 'cancelled':   return TaskStatus.cancelled;
      case 'disputed':    return TaskStatus.disputed;
      default:            return TaskStatus.open;
    }
  }

  /// Returns true if the task is in a terminal state.
  bool get isTerminal => this == TaskStatus.completed ||
                         this == TaskStatus.cancelled ||
                         this == TaskStatus.disputed;

  /// Returns true if the task requires OTP interaction.
  bool get requiresOtp => this == TaskStatus.matched ||
                          this == TaskStatus.inProgress;
}
