import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';

/// A shimmer placeholder card shown while tasks load.
class TaskCardSkeleton extends StatelessWidget {
  const TaskCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SkeletonBox(width: 44, height: 44, radius: 12),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(width: double.infinity, height: 16),
                    const Gap(6),
                    _SkeletonBox(width: 100, height: 12),
                  ],
                ),
              ),
              const Gap(12),
              _SkeletonBox(width: 64, height: 24, radius: 20),
            ],
          ),
          const Gap(14),
          _SkeletonBox(width: double.infinity, height: 12),
          const Gap(6),
          _SkeletonBox(width: 200, height: 12),
          const Gap(14),
          Row(
            children: [
              _SkeletonBox(width: 60, height: 24, radius: 8),
              const Gap(8),
              _SkeletonBox(width: 80, height: 24, radius: 8),
            ],
          ),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: 1500.ms,
          color: AppColors.borderColor.withOpacity(0.6),
        );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    this.radius = 6,
  });
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A list of skeleton cards for loading states.
class TaskListSkeleton extends StatelessWidget {
  const TaskListSkeleton({super.key, this.count = 4});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (i) => const TaskCardSkeleton()),
    );
  }
}
