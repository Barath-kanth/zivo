import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/task/task_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/ui/_shared/task_status_badge.dart';
import 'package:hyperlocal/ui/_shared/task_photo_gallery.dart';
import 'package:hyperlocal/blocs/mode/mode_cubit.dart';

/// Helper Home — Feed of nearby human tasks to pick up.
class HelperHomeScreen extends StatefulWidget {
  const HelperHomeScreen({super.key});

  @override
  State<HelperHomeScreen> createState() => _HelperHomeScreenState();
}

class _HelperHomeScreenState extends State<HelperHomeScreen> {
  String _selectedFilter = 'All';

  final _filters = [
    'All', '🚶 Queue', '🛒 Grocery', '🧹 Cleaning',
    '📦 Moving', '📚 Tutoring', '💻 Tech', '🐕 Pet Care',
  ];

  @override
  void initState() {
    super.initState();
    context.read<TaskBloc>()
      ..add(TaskFetchNearbyTasks())
      ..add(TaskSubscribeToFeed());
  }

  Color _catColor(TaskCategory cat) {
    switch (cat) {
      case TaskCategory.queueStanding:     return AppColors.catQueue;
      case TaskCategory.laundry:           return AppColors.catLaundry;
      case TaskCategory.groceryRun:        return AppColors.catGrocery;
      case TaskCategory.homeCleaning:      return AppColors.catCleaning;
      case TaskCategory.homeCooking:       return AppColors.catCooking;
      case TaskCategory.movingHelp:        return AppColors.catMoving;
      case TaskCategory.tutoring:          return AppColors.catTutoring;
      case TaskCategory.techHelp:          return AppColors.catTech;
      case TaskCategory.petCare:           return AppColors.catPetCare;
      case TaskCategory.tailoring:         return AppColors.catTailoring;
      case TaskCategory.driver:            return AppColors.catDriver;
      case TaskCategory.errandRun:         return AppColors.catErrand;
      case TaskCategory.gardening:         return AppColors.catGarden;
      case TaskCategory.documentWork:      return AppColors.catDocument;
      case TaskCategory.hospitalCompanion: return AppColors.catHospital;
      case TaskCategory.babysitting:       return AppColors.catBabysit;
      case TaskCategory.elderCare:         return AppColors.catElderCare;
      case TaskCategory.eventHelp:         return AppColors.catEvent;
      case TaskCategory.photography:       return AppColors.catPhoto;
      case TaskCategory.homeRepair:        return AppColors.catRepair;
      case TaskCategory.other:             return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TaskBloc, TaskState>(
      listenWhen: (prev, next) =>
          next is TaskAccepted || next is TaskFailure,
      listener: (context, state) {
        if (state is TaskFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.message.replaceFirst('Exception: ', ''),
                style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
              ),
              backgroundColor: AppColors.errorColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        if (state is! TaskAccepted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Job accepted — ask the client for Start OTP.',
              style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.helperAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go('/job/${state.task.id}/active');
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: CustomScrollView(
          slivers: [
            _buildHeader(),
            _buildEarningsBar(),
            _buildFilterRow(),
            _buildFeedTitle(),
            _buildFeed(),
            const SliverToBoxAdapter(child: Gap(100)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE8F5E9), AppColors.backgroundDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                final name = state is AuthAuthenticated
                    ? state.profile.fullName.split(' ').first
                    : 'Helper';
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.helperAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: AppColors.helperAccent
                                          .withOpacity(0.4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: AppColors.helperAccent,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.helperAccent
                                                .withOpacity(0.8),
                                            blurRadius: 5,
                                            spreadRadius: 1,
                                          )
                                        ],
                                      ),
                                    )
                                        .animate(
                                            onPlay: (c) => c.repeat())
                                        .scaleXY(end: 1.4, duration: 900.ms),
                                    const Gap(5),
                                    Text(
                                      'HELPER MODE — LIVE',
                                      style:
                                          AppTextStyles.capsLabel.copyWith(
                                        color: AppColors.helperAccent,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Gap(10),
                          Text(
                            'Ready to help, $name?',
                            style: AppTextStyles.displayMedium
                                .copyWith(fontSize: 24),
                          )
                              .animate()
                              .fadeIn(duration: 400.ms)
                              .slideX(begin: -0.06),
                          Text(
                            'Jobs near you update in real-time.',
                            style: AppTextStyles.bodyMedium,
                          ).animate().fadeIn(delay: 100.ms),
                        ],
                      ),
                    ),
                    _buildSwitchToClientPill(context),
                    const Gap(8),
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.cardDark,
                            title: const Text('Notifications'),
                            content: const Text('No new notifications at this time.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('OK', style: TextStyle(color: AppColors.helperAccent)),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.cardDark,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.borderColor),
                        ),
                        child: const Icon(Icons.notifications_outlined,
                            color: AppColors.textSecondary, size: 20),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchToClientPill(BuildContext context) {
    return BlocBuilder<ModeCubit, ModeState>(
      builder: (context, state) {
        final isToggling = state is ModeToggling;
        return GestureDetector(
          onTap: isToggling ? null : () {
            context.read<ModeCubit>().toggleMode();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_search_rounded, color: AppColors.accent, size: 16),
                const Gap(6),
                Text(
                  'Client Mode',
                  style: AppTextStyles.capsLabel.copyWith(
                    color: AppColors.accent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEarningsBar() {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final profile =
            state is AuthAuthenticated ? state.profile : null;
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: AppColors.helperGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.helperAccent.withOpacity(0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _EarningStat(
                    emoji: '💰',
                    label: 'Total Earned',
                    value:
                        'LKR ${(profile?.helperEarnings ?? 0.0).toStringAsFixed(2)}',
                  ),
                  _Divider(),
                  _EarningStat(
                    emoji: '✅',
                    label: 'Jobs Done',
                    value: '${profile?.totalTasksHelped ?? 0}',
                  ),
                  _Divider(),
                  _EarningStat(
                    emoji: '⭐',
                    label: 'Rating',
                    value:
                        '${(profile?.ratingAsHelper ?? 0.0).toStringAsFixed(1)}',
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
          ),
        );
      },
    );
  }

  Widget _buildFilterRow() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 4),
        child: SizedBox(
          height: 36,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: _filters.length,
            separatorBuilder: (_, __) => const Gap(8),
            itemBuilder: (ctx, i) {
              final isSelected = _filters[i] == _selectedFilter;
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedFilter = _filters[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.helperAccent
                        : AppColors.cardDark,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.helperAccent
                          : AppColors.borderColor,
                    ),
                  ),
                  child: Text(
                    _filters[i],
                    style: AppTextStyles.bodySmall.copyWith(
                      color: isSelected
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFeedTitle() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: BlocBuilder<TaskBloc, TaskState>(
          builder: (ctx, state) {
            final count =
                state is TaskNearbyLoaded ? state.tasks.length : 0;
            return Row(
              children: [
                Text('Nearby Jobs', style: AppTextStyles.headingSmall),
                const Gap(8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.helperAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count open',
                    style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.helperAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 11),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFeed() {
    return BlocBuilder<TaskBloc, TaskState>(
      builder: (context, state) {
        if (state is TaskLoading) {
          return const SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(
                  color: AppColors.helperAccent, strokeWidth: 2),
            ),
          );
        }

        var tasks = state is TaskNearbyLoaded ? state.tasks : <Task>[];
        if (_selectedFilter != 'All') {
          tasks = tasks.where((t) {
            if (_selectedFilter == '🚶 Queue') return t.category == TaskCategory.queueStanding;
            if (_selectedFilter == '🛒 Grocery') return t.category == TaskCategory.groceryRun;
            if (_selectedFilter == '🧹 Cleaning') return t.category == TaskCategory.homeCleaning;
            if (_selectedFilter == '📦 Moving') return t.category == TaskCategory.movingHelp;
            if (_selectedFilter == '📚 Tutoring') return t.category == TaskCategory.tutoring;
            if (_selectedFilter == '💻 Tech') return t.category == TaskCategory.techHelp;
            if (_selectedFilter == '🐕 Pet Care') return t.category == TaskCategory.petCare;
            return true;
          }).toList();
        }

        if (tasks.isEmpty) {
          final auth = context.read<AuthBloc>().state;
          final helperId =
              auth is AuthAuthenticated ? auth.profile.id : null;
          final active = context
              .read<TaskBloc>()
              .getActiveTaskForHelper(helperId: helperId);
          return SliverFillRemaining(
            child: _EmptyFeed(
              hasActiveJob: active != null,
              onOpenActive: active == null
                  ? null
                  : () => context.go('/job/${active.id}/active'),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _JobCard(
                task: tasks[i],
                index: i,
                color: _catColor(tasks[i].category),
              ),
              childCount: tasks.length,
            ),
          ),
        );
      },
    );
  }
}

// ── Job Card ──────────────────────────────────────────────────────────────────

class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.task, required this.index});
  final Task task;
  final int index;

  Color _catColor(TaskCategory cat) {
    switch (cat) {
      case TaskCategory.queueStanding:     return AppColors.catQueue;
      case TaskCategory.laundry:           return AppColors.catLaundry;
      case TaskCategory.groceryRun:        return AppColors.catGrocery;
      case TaskCategory.homeCleaning:      return AppColors.catCleaning;
      case TaskCategory.homeCooking:       return AppColors.catCooking;
      case TaskCategory.movingHelp:        return AppColors.catMoving;
      case TaskCategory.tutoring:          return AppColors.catTutoring;
      case TaskCategory.techHelp:          return AppColors.catTech;
      case TaskCategory.petCare:           return AppColors.catPetCare;
      case TaskCategory.tailoring:         return AppColors.catTailoring;
      case TaskCategory.driver:            return AppColors.catDriver;
      case TaskCategory.errandRun:         return AppColors.catErrand;
      case TaskCategory.gardening:         return AppColors.catGarden;
      case TaskCategory.documentWork:      return AppColors.catDocument;
      case TaskCategory.hospitalCompanion: return AppColors.catHospital;
      case TaskCategory.babysitting:       return AppColors.catBabysit;
      case TaskCategory.elderCare:         return AppColors.catElderCare;
      case TaskCategory.eventHelp:         return AppColors.catEvent;
      case TaskCategory.photography:       return AppColors.catPhoto;
      case TaskCategory.homeRepair:        return AppColors.catRepair;
      case TaskCategory.other:             return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _catColor(task.category);
    return _JobCard(task: task, index: index, color: color);
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard(
      {required this.task, required this.index, required this.color});
  final Task task;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Text(task.category.emoji,
                    style: const TextStyle(fontSize: 18)),
                const Gap(8),
                Text(
                  task.category.displayName.toUpperCase(),
                  style: AppTextStyles.capsLabel.copyWith(
                      color: color, fontSize: 10, letterSpacing: 1.0),
                ),
                const Spacer(),
                if (task.locationLabel != null)
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 12, color: AppColors.textMuted),
                      const Gap(3),
                      Text(task.locationLabel!,
                          style: AppTextStyles.bodySmall
                              .copyWith(fontSize: 10)),
                    ],
                  ),
              ],
            ),
          ),

          // Task body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title,
                    style: AppTextStyles.headingSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const Gap(6),
                Text(task.description,
                    style: AppTextStyles.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
                if (task.photoUrls.isNotEmpty) ...[
                  const Gap(10),
                  TaskPhotoGallery(
                    photoUrls: task.photoUrls,
                    height: 80,
                    label: 'Client photos',
                  ),
                ],
                const Gap(14),
                Row(
                  children: [
                    // Pay
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('You earn',
                            style: AppTextStyles.bodySmall
                                .copyWith(fontSize: 10)),
                        Text(
                          'LKR ${(task.totalAmount * 0.9).toStringAsFixed(2)}',
                          style: AppTextStyles.headingSmall.copyWith(
                              color: AppColors.helperAccent),
                        ),
                      ],
                    ),
                    const Gap(16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Duration',
                            style: AppTextStyles.bodySmall
                                .copyWith(fontSize: 10)),
                        Text(
                          '${task.estimatedHours}h',
                          style: AppTextStyles.headingSmall,
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Accept button
                    ElevatedButton(
                      onPressed: () {
                        final authState =
                            context.read<AuthBloc>().state;
                        if (authState is AuthAuthenticated) {
                          context.read<TaskBloc>().add(TaskAccept(
                              taskId: task.id,
                              helperId: authState.profile.id));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.helperAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: Text(
                        'Accept Job',
                        style: AppTextStyles.capsLabel.copyWith(
                            color: Colors.white,
                            fontSize: 11,
                            letterSpacing: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 60 * index))
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.07);
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _EarningStat extends StatelessWidget {
  const _EarningStat(
      {required this.emoji, required this.label, required this.value});
  final String emoji;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const Gap(4),
          Text(value,
              style: AppTextStyles.headingSmall.copyWith(
                  color: Colors.white, fontSize: 15)),
          Text(label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: Colors.white60, fontSize: 10)),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
        width: 1, height: 40, color: Colors.white.withOpacity(0.15));
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({this.hasActiveJob = false, this.onOpenActive});

  final bool hasActiveJob;
  final VoidCallback? onOpenActive;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🔍', style: const TextStyle(fontSize: 48))
                .animate(onPlay: (c) => c.repeat())
                .shimmer(
                    duration: 2000.ms,
                    color: AppColors.helperAccent.withOpacity(0.3)),
            const Gap(16),
            Text(
              hasActiveJob
                  ? 'Your accepted job is under Active'
                  : 'No jobs nearby right now',
              style: AppTextStyles.headingSmall,
              textAlign: TextAlign.center,
            ),
            const Gap(8),
            Text(
              hasActiveJob
                  ? 'Open jobs leave this list once you accept them. Continue on the Active tab with Start OTP.'
                  : 'New tasks appear here the moment someone posts near you. Stay on this screen.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (hasActiveJob && onOpenActive != null) ...[
              const Gap(20),
              ElevatedButton(
                onPressed: onOpenActive,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.helperAccent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Open Active Job'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
