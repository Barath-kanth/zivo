import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/models/task_status.dart';
import 'package:hyperlocal/ui/_shared/category_icon.dart';

/// Compact front-page chip — title only. Tap opens [showTaskJourneySheet].
class TaskNameChip extends StatelessWidget {
  const TaskNameChip({
    super.key,
    required this.task,
    this.isHelper = false,
  });

  final Task task;
  final bool isHelper;

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showTaskJourneySheet(
          context,
          task: task,
          isHelper: isHelper,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              CategoryIcon(task.category, size: 16),
              const Gap(8),
              Expanded(
                child: Text(
                  task.title.trim().isEmpty
                      ? task.category.displayName
                      : task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              _StatusDot(status: task.status),
              const Gap(4),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final live =
        status == TaskStatus.matched || status == TaskStatus.inProgress;
    final color = switch (status) {
      TaskStatus.completed => AppColors.successColor,
      TaskStatus.cancelled || TaskStatus.disputed => AppColors.errorColor,
      _ when live => AppColors.helperAccent,
      _ => AppColors.textMuted,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Straight vertical journey timeline for one task (Uber Activity style).
Future<void> showTaskJourneySheet(
  BuildContext context, {
  required Task task,
  bool isHelper = false,
}) {
  final palette = ZivoPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: palette.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _TaskJourneyBody(task: task, isHelper: isHelper),
  );
}

class _JourneyStep {
  const _JourneyStep({
    required this.title,
    required this.body,
    required this.done,
    required this.current,
    required this.accent,
  });
  final String title;
  final String body;
  final bool done;
  final bool current;
  final Color accent;
}

class _TaskJourneyBody extends StatelessWidget {
  const _TaskJourneyBody({required this.task, required this.isHelper});
  final Task task;
  final bool isHelper;

  List<_JourneyStep> _steps() {
    final s = task.status;
    final matched = s == TaskStatus.matched ||
        s == TaskStatus.inProgress ||
        s == TaskStatus.completed ||
        s == TaskStatus.disputed;
    final started =
        s == TaskStatus.inProgress || s == TaskStatus.completed;
    final done = s == TaskStatus.completed;
    final cancelled =
        s == TaskStatus.cancelled || s == TaskStatus.disputed;

    if (cancelled) {
      return [
        _JourneyStep(
          title: 'Posted',
          body: task.category.displayName,
          done: true,
          current: false,
          accent: AppColors.helperAccent,
        ),
        _JourneyStep(
          title: 'Cancelled',
          body: 'This job was cancelled.',
          done: true,
          current: true,
          accent: AppColors.errorColor,
        ),
      ];
    }

    return [
      _JourneyStep(
        title: 'Posted',
        body: '${task.category.displayName} · ${AppConfig.money(task.totalAmount)}',
        done: true,
        current: s == TaskStatus.open,
        accent: AppColors.helperAccent,
      ),
      _JourneyStep(
        title: 'Matched',
        body: isHelper
            ? 'You accepted this job'
            : (task.helperDisplayName?.trim().isNotEmpty == true
                ? 'Helper ${task.helperDisplayName}'
                : 'Waiting for a helper'),
        done: matched,
        current: s == TaskStatus.matched,
        accent: const Color(0xFF276EF1),
      ),
      _JourneyStep(
        title: 'In progress',
        body: task.startOtp != null
            ? 'Start OTP ready · work underway'
            : 'Start when both sides confirm',
        done: started || done,
        current: s == TaskStatus.inProgress,
        accent: const Color(0xFFB54708),
      ),
      _JourneyStep(
        title: 'Completed',
        body: done
            ? 'Job finished · escrow releasing'
            : 'End OTP closes the job',
        done: done,
        current: done,
        accent: AppColors.successColor,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final steps = _steps();
    final title =
        task.title.trim().isEmpty ? task.category.displayName : task.title;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const Gap(14),
            Row(
              children: [
                CategoryIcon(task.category, size: 18),
                const Gap(8),
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            if (task.description.trim().isNotEmpty) ...[
              const Gap(4),
              Text(
                task.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 12,
                  color: palette.textMuted,
                  height: 1.3,
                ),
              ),
            ],
            const Gap(18),
            for (var i = 0; i < steps.length; i++)
              _StraightTimelineRow(
                step: steps[i],
                isLast: i == steps.length - 1,
              ),
            const Gap(16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push(
                        AppRoutes.chatFor(task.id, title: title),
                      );
                    },
                    child: const Text('Chat'),
                  ),
                ),
                const Gap(8),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      if (isHelper) {
                        context.push('/job/${task.id}/active');
                      } else {
                        context.push('/task/${task.id}/track');
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.onAccent,
                    ),
                    child: Text(isHelper ? 'Open job' : 'Track'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Single-column stepper: node + solid line on the left, copy on the right.
class _StraightTimelineRow extends StatelessWidget {
  const _StraightTimelineRow({
    required this.step,
    required this.isLast,
  });

  final _JourneyStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    final active = step.done || step.current;
    final lineColor = step.done
        ? step.accent.withValues(alpha: 0.55)
        : palette.border;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: active ? step.accent : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active ? step.accent : palette.border,
                      width: 2,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: lineColor,
                    ),
                  ),
              ],
            ),
          ),
          const Gap(12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title.toUpperCase(),
                    style: AppTextStyles.capsLabel.copyWith(
                      fontSize: 10,
                      letterSpacing: 0.6,
                      color: active ? step.accent : palette.textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Gap(2),
                  Text(
                    step.body,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 12,
                      height: 1.3,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
