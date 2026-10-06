import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/otp/otp_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/models/task_status.dart';
import 'package:hyperlocal/blocs/task/task_bloc.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/ui/_shared/task_status_badge.dart';
import 'package:hyperlocal/ui/_shared/empty_state_widget.dart';
import 'package:hyperlocal/ui/_shared/trust_review_sheet.dart';

class TaskTrackingScreen extends StatefulWidget {
  const TaskTrackingScreen({super.key, required this.taskId});
  final String taskId;

  @override
  State<TaskTrackingScreen> createState() => _TaskTrackingScreenState();
}

class _TaskTrackingScreenState extends State<TaskTrackingScreen> {
  late OtpBloc _otpBloc;

  @override
  void initState() {
    super.initState();
    _otpBloc = context.read<OtpBloc>();
    _otpBloc.add(OtpSubscribeToTask(widget.taskId));
  }

  @override
  void dispose() {
    _otpBloc.add(OtpUnsubscribeFromTask());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        title: const Text('Task Tracking'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Chat with helper',
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            onPressed: () {
              context.push(AppRoutes.chatFor(widget.taskId));
            },
          ),
        ],
      ),
      body: BlocBuilder<OtpBloc, OtpState>(
        builder: (context, state) {
          if (state is OtpInitial || state is OtpVerifying) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }

          Task? task;
          if (state is OtpStateOpen) task = state.task;
          if (state is OtpStateMatched) task = state.task;
          if (state is OtpStateInProgress) task = state.task;
          if (state is OtpStateCompleted) task = state.task;
          if (state is OtpFailure) {
            return EmptyStateWidget(
              icon: Icons.error_outline,
              title: 'Error',
              subtitle: state.message,
              color: AppColors.errorColor,
            );
          }

          if (task == null) return const SizedBox.shrink();
          final t = task;

          return CustomScrollView(
            slivers: [
              _buildMapSliver(t),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTaskSummary(t),
                      if (t.status == TaskStatus.matched ||
                          t.status == TaskStatus.inProgress ||
                          t.status == TaskStatus.completed) ...[
                        const Gap(12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => context.push(
                              AppRoutes.chatFor(
                                widget.taskId,
                                title: t.title,
                              ),
                            ),
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                            label: const Text('Chat with helper'),
                          ),
                        ),
                      ],
                      if (t.status == TaskStatus.matched ||
                          t.status == TaskStatus.inProgress ||
                          t.status == TaskStatus.disputed) ...[
                        const Gap(8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => showTrustReviewSheet(
                              context,
                              taskId: widget.taskId,
                            ),
                            icon: const Icon(Icons.gavel_rounded, size: 18),
                            label: const Text('Trust Arbitrator'),
                          ),
                        ),
                      ],
                      const Gap(20),
                      _buildOtpSection(state, t),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMapSliver(Task task) {
    return SliverToBoxAdapter(
      child: Container(
        height: 160,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderColor),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on_rounded,
                color: AppColors.accent, size: 36),
            const SizedBox(height: 8),
            Text(
              task.locationLabel ?? task.locationAddress ?? 'Task Location',
              style: AppTextStyles.headingSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Lat: ${task.location.latitude.toStringAsFixed(4)}, '
              'Lon: ${task.location.longitude.toStringAsFixed(4)}',
              style: AppTextStyles.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskSummary(Task task) {
    return Container(
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
              Text(task.category.emoji, style: const TextStyle(fontSize: 22)),
              const Gap(10),
              Expanded(child: Text(task.title, style: AppTextStyles.headingSmall)),
              TaskStatusBadge(status: task.status),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MetaItem(icon: Icons.schedule_rounded, label: '${task.estimatedHours}h estimated'),
              _MetaItem(icon: Icons.payments_outlined, label: 'LKR ${task.totalAmount.toStringAsFixed(2)} total'),
              _MetaItem(icon: Icons.location_on_rounded, label: task.locationLabel ?? 'Location'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOtpSection(OtpState state, Task task) {
    if (state is OtpStateOpen) {
      return _buildApplicantsSection(task);
    }

    if (state is OtpStateMatched) {
      return _OtpDisplayCard(
        phase: 'Start',
        otp: task.startOtp ?? '------',
        title: 'Share this code with your Helper',
        subtitle: 'The helper will enter this 6-digit code to start the task.',
        gradientColors: [AppColors.accent, const Color(0xFF4F46E5)],
        errorMessage: state.errorMessage,
      );
    }

    if (state is OtpStateInProgress) {
      return _OtpDisplayCard(
        phase: 'End',
        otp: task.endOtp ?? '------',
        title: 'Task in progress!',
        subtitle: 'When the task is done, share this End OTP with your helper.',
        gradientColors: [AppColors.helperAccent, const Color(0xFF0F766E)],
        errorMessage: state.errorMessage,
      );
    }

    if (state is OtpStateCompleted) {
      return _CompletedCard(task: task);
    }

    return const SizedBox.shrink();
  }

  Widget _buildApplicantsSection(Task task) {
    final applicants = <_Applicant>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Applicants (${applicants.length})', style: AppTextStyles.headingMedium),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        const Gap(4),
        Text(
          'Waiting for qualified helpers to apply. You will see ratings and details here once someone applies.',
          style: AppTextStyles.bodyMedium,
        ),
        const Gap(16),
        if (applicants.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No applicants yet',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ),
          )
        else
          ...applicants.map((app) => _buildApplicantCard(task, app)),
      ],
    );
  }

  Widget _buildApplicantCard(Task task, _Applicant applicant) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(applicant.avatar, style: const TextStyle(fontSize: 32)),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(applicant.name, style: AppTextStyles.headingSmall),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Color(0xFFFFC043), size: 16),
                        const Gap(3),
                        Text(
                          '${applicant.rating} rating',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'LKR ${applicant.hourlyRate.toStringAsFixed(2)}/hr',
                    style: AppTextStyles.headingSmall.copyWith(color: AppColors.helperAccent),
                  ),
                  Text('Estimated total', style: AppTextStyles.bodySmall),
                ],
              ),
            ],
          ),
          const Divider(height: 20),
          Text(
            applicant.credentials,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: AppColors.textPrimary,
            ),
          ),
          const Gap(4),
          Text(
            applicant.bio,
            style: AppTextStyles.bodyMedium.copyWith(fontSize: 12, color: AppColors.textSecondary),
          ),
          const Gap(16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                // 1. Accept Task in TaskBloc (stores matched status in memory)
                context.read<TaskBloc>().add(TaskAccept(
                  taskId: task.id,
                  helperId: applicant.helperId,
                ));
                // 2. Dispatch updated task directly to OtpBloc for instant reactive state transition
                final updatedTask = Task(
                  id: task.id,
                  clientId: task.clientId,
                  helperId: applicant.helperId,
                  title: task.title,
                  description: task.description,
                  category: task.category,
                  estimatedHours: task.estimatedHours,
                  hourlyRate: applicant.hourlyRate,
                  totalAmount: applicant.hourlyRate * task.estimatedHours,
                  location: task.location,
                  locationAddress: task.locationAddress,
                  locationLabel: task.locationLabel,
                  status: TaskStatus.matched,
                  startOtp: '123456',
                  endOtp: '654321',
                  matchedAt: DateTime.now(),
                  createdAt: task.createdAt,
                );
                context.read<OtpBloc>().add(OtpTaskRealtimeUpdated(updatedTask));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Hire ${applicant.name.split(' ').first}', style: AppTextStyles.buttonLabel),
            ),
          ),
        ],
      ),
    );
  }

  // Applicants come from live quotes / accept flow — no mock list.
}

class _Applicant {
  const _Applicant({
    required this.name,
    required this.avatar,
    required this.rating,
    required this.credentials,
    required this.bio,
    required this.hourlyRate,
    required this.helperId,
  });
  final String name;
  final String avatar;
  final double rating;
  final String credentials;
  final String bio;
  final double hourlyRate;
  final String helperId;
}

class _OtpDisplayCard extends StatelessWidget {
  const _OtpDisplayCard({
    required this.phase,
    required this.otp,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
    this.errorMessage,
  });

  final String phase;
  final String otp;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [gradientColors[0].withOpacity(0.15), Colors.transparent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gradientColors[0].withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: gradientColors[0].withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$phase OTP',
                  style: AppTextStyles.capsLabel.copyWith(color: gradientColors[0]),
                ),
              ),
            ],
          ),
          const Gap(16),
          Text(title, style: AppTextStyles.headingMedium),
          const Gap(6),
          Text(subtitle, style: AppTextStyles.bodyMedium),
          const Gap(24),
          // OTP Display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.otpBoxBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: gradientColors[0].withOpacity(0.5), width: 2),
            ),
            child: Text(
              otp.split('').join(' '),
              textAlign: TextAlign.center,
              style: AppTextStyles.otpDigit.copyWith(
                color: gradientColors[0],
                letterSpacing: 12,
              ),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
              .shimmer(duration: 3000.ms, color: gradientColors[0].withOpacity(0.3)),
          if (errorMessage != null) ...[
            const Gap(12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.errorColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.errorColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.errorColor, size: 16),
                  const Gap(8),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.errorColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95));
  }
}

class _CompletedCard extends StatelessWidget {
  const _CompletedCard({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.successColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.successColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.successColor, size: 56),
          const Gap(12),
          Text('Task Completed!', style: AppTextStyles.headingMedium),
          const Gap(4),
          Text(
            'The escrow has been released to your helper.',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const Gap(20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.successColor),
              child: const Text('Back to Home'),
            ),
          ),
        ],
      ),
    ).animate().scale(duration: 500.ms, curve: Curves.elasticOut);
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const Gap(4),
        Text(label, style: AppTextStyles.bodySmall),
      ],
    );
  }
}
