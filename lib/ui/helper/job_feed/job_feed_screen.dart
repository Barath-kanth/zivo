import 'package:hyperlocal/ui/_shared/category_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/task/task_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/services/policy/qualification_gate.dart';
import 'package:hyperlocal/core/utils/auth_gate.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/data/repositories/trust_repository.dart';
import 'package:hyperlocal/ui/_shared/task_status_badge.dart';
import 'package:hyperlocal/ui/_shared/empty_state_widget.dart';
import 'package:hyperlocal/ui/_shared/task_photo_gallery.dart';

class JobFeedScreen extends StatefulWidget {
  const JobFeedScreen({super.key});

  @override
  State<JobFeedScreen> createState() => _JobFeedScreenState();
}

class _JobFeedScreenState extends State<JobFeedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isMapView = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    context.read<TaskBloc>()
      ..add(TaskFetchNearbyTasks())
      ..add(TaskSubscribeToFeed());
  }

  @override
  void dispose() {
    _tabController.dispose();
    context.read<TaskBloc>().add(TaskUnsubscribeFromFeed());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: CustomScrollView(
        slivers: [
          _buildHeader(),
          _buildViewToggle(),
          _buildFeed(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.helperAccent.withOpacity(0.12),
              AppColors.backgroundDark,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.helperAccent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.helperAccent.withOpacity(0.6),
                            blurRadius: 6,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ).animate(onPlay: (c) => c.repeat())
                        .scaleXY(end: 1.4, duration: 800.ms, curve: Curves.easeInOut),
                    const Gap(8),
                    Text(
                      'Nearby opportunities',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.helperAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.read<TaskBloc>().add(TaskFetchNearbyTasks()),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.helperAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.helperAccent.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.refresh_rounded, color: AppColors.helperAccent, size: 18),
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                Text('Jobs Near You', style: AppTextStyles.headingLarge),
                Text(
                  'Tasks within 5km · Sorted by distance',
                  style: AppTextStyles.bodyMedium,
                ).animate().fadeIn(delay: 100.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewToggle() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderColor),
          ),
          child: Row(
            children: [
              _ViewToggleTab(
                label: 'List View',
                icon: Icons.list_rounded,
                isSelected: !_isMapView,
                onTap: () => setState(() => _isMapView = false),
                activeColor: AppColors.helperAccent,
              ),
              _ViewToggleTab(
                label: 'Map View',
                icon: Icons.map_rounded,
                isSelected: _isMapView,
                onTap: () => setState(() => _isMapView = true),
                activeColor: AppColors.helperAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeed() {
    return BlocBuilder<TaskBloc, TaskState>(
      builder: (context, state) {
        if (state is TaskLoading) {
          return SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.helperAccent),
            ),
          );
        }

        if (state is TaskFailure) {
          return SliverFillRemaining(
            child: EmptyStateWidget(
              icon: Icons.wifi_off_rounded,
              title: 'Connection Error',
              subtitle: state.message,
              color: AppColors.errorColor,
            ),
          );
        }

        List<Task> tasks = [];
        if (state is TaskNearbyLoaded) tasks = state.tasks;
        final me = context.read<AuthBloc>().state;
        if (me is AuthAuthenticated) {
          tasks = tasks.where((t) => t.clientId != me.profile.id).toList();
        }

        if (tasks.isEmpty) {
          return SliverFillRemaining(
            child: EmptyStateWidget(
              icon: Icons.search_off_rounded,
              title: 'No jobs nearby',
              subtitle: 'No open tasks within 5km. Check back soon — new tasks appear in real time.',
              color: AppColors.helperAccent,
            ),
          );
        }

        if (_isMapView) {
          return SliverFillRemaining(
            child: _MapView(tasks: tasks),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => JobCard(task: tasks[i], index: i),
              childCount: tasks.length,
            ),
          ),
        );
      },
    );
  }
}

class _ViewToggleTab extends StatelessWidget {
  const _ViewToggleTab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.activeColor,
  });
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? activeColor : AppColors.textMuted),
              const Gap(6),
              Text(
                label,
                style: AppTextStyles.labelLarge.copyWith(
                  color: isSelected ? activeColor : AppColors.textMuted,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.task, required this.index});
  final Task task;
  final int index;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final helperId = auth is AuthAuthenticated ? auth.profile.id : null;

    return GestureDetector(
      onTap: () => _showJobDetail(context, helperId),
      child: Container(
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.helperAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.helperAccent.withOpacity(0.3)),
                  ),
                  child: Center(
                    child: CategoryIcon(task.category, size: 20),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title, style: AppTextStyles.headingSmall),
                      const Gap(2),
                      Text(task.category.displayName, style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      AppConfig.money(task.totalAmount),
                      style: AppTextStyles.moneyMedium.copyWith(color: AppColors.helperAccent),
                    ),
                    Text('total', style: AppTextStyles.bodySmall),
                  ],
                ),
              ],
            ),
            const Gap(12),
            Text(
              task.description,
              style: AppTextStyles.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (task.photoUrls.isNotEmpty) ...[
              const Gap(10),
              TaskPhotoGallery(
                photoUrls: task.photoUrls,
                height: 72,
                label: '${task.photoUrls.length} photo${task.photoUrls.length == 1 ? '' : 's'}',
              ),
            ],
            const Gap(12),
            Row(
              children: [
                _Chip(
                  icon: Icons.schedule_outlined,
                  label: '${task.estimatedHours}h',
                  color: AppColors.accent,
                ),
                const Gap(8),
                _Chip(
                  icon: Icons.near_me_rounded,
                  label: task.distanceKm != null
                      ? '${task.distanceKm!.toStringAsFixed(1)}km away'
                      : 'Nearby',
                  color: AppColors.helperAccent,
                ),
                if (task.locationLabel != null) ...[
                  const Gap(8),
                  Expanded(
                    child: _Chip(
                      icon: Icons.location_on_outlined,
                      label: task.locationLabel!,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ).animate(delay: Duration(milliseconds: index * 60))
          .fadeIn(duration: 350.ms)
          .slideY(begin: 0.1),
    );
  }

  void _showJobDetail(BuildContext context, String? helperId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Gap(20),
              Row(
                children: [
                  CategoryIcon(task.category, size: 28),
                  const Gap(12),
                  Expanded(child: Text(task.title, style: AppTextStyles.headingMedium)),
                  TaskStatusBadge(status: task.status),
                ],
              ),
              const Gap(12),
              Text(task.description, style: AppTextStyles.bodyLarge),
              if (task.photoUrls.isNotEmpty) ...[
                const Gap(16),
                TaskPhotoGallery(photoUrls: task.photoUrls, height: 120),
              ],
              const Gap(20),
              // Earnings breakdown
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.helperAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.helperAccent.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    _EarningsRow(label: 'Duration', value: '${task.estimatedHours} hours'),
                    _EarningsRow(label: 'Rate', value: '${AppConfig.money(task.hourlyRate)}/hr'),
                    const Divider(height: 16),
                    _EarningsRow(
                      label: 'Your Earnings',
                      value: AppConfig.money(task.totalAmount * 0.9),
                      isTotal: true,
                      color: AppColors.helperAccent,
                    ),
                    _EarningsRow(
                      label: 'Platform Fee',
                      value: '${AppConfig.money(task.totalAmount * 0.1)} (10%)',
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
              const Gap(28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        if (!await requireAuth(
                          context,
                          returnTo: AppRoutes.jobFeed,
                        )) {
                          return;
                        }
                        if (!context.mounted) return;
                        if (!await requireVerified(
                          context,
                          returnTo: AppRoutes.jobFeed,
                        )) {
                          return;
                        }
                        if (!context.mounted) return;
                        final auth = context.read<AuthBloc>().state;
                        if (auth is! AuthAuthenticated) return;
                        await _sendQuote(
                          ctx,
                          context,
                          task,
                          auth.profile.id,
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: AppColors.helperAccent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Send quote',
                        style: AppTextStyles.buttonLabel.copyWith(
                          color: AppColors.helperAccent,
                        ),
                      ),
                    ),
                  ),
                  const Gap(10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (!await requireAuth(
                          context,
                          returnTo: AppRoutes.jobFeed,
                        )) {
                          return;
                        }
                        if (!context.mounted) return;
                        final auth = context.read<AuthBloc>().state;
                        if (auth is! AuthAuthenticated) return;
                        await _acceptWithGates(
                          ctx,
                          context,
                          task,
                          auth.profile.id,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.helperAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Accept',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(8),
              Text(
                'Accepting means you confirm the work is lawful. Driving / tutoring / care jobs need verified qualifications.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _acceptWithGates(
    BuildContext sheetCtx,
    BuildContext rootCtx,
    Task task,
    String helperId,
  ) async {
    if (task.clientId == helperId) {
      if (!rootCtx.mounted) return;
      ScaffoldMessenger.of(rootCtx).showSnackBar(
        const SnackBar(
          content: Text(
            'You cannot accept a task you posted. Switch accounts or wait for a helper.',
          ),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }
    final quals =
        await rootCtx.read<TrustRepository>().getQualifications(helperId);
    final msg = QualificationGate.missingMessage(
      category: task.category,
      quals: quals,
    );
    if (msg.isNotEmpty) {
      if (!rootCtx.mounted) return;
      ScaffoldMessenger.of(rootCtx).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.errorColor,
          action: SnackBarAction(
            label: 'Add',
            textColor: Colors.white,
            onPressed: () => rootCtx.push(AppRoutes.qualifications),
          ),
        ),
      );
      return;
    }
    if (!sheetCtx.mounted || !rootCtx.mounted) return;
    Navigator.pop(sheetCtx);
    try {
      final ranking =
          await rootCtx.read<TaskRepository>().matchHelpers(task.id);
      if (rootCtx.mounted) {
        await _showPillarCMatch(rootCtx, ranking);
      }
    } catch (_) {}
    if (!rootCtx.mounted) return;
    // Accept first, then open Active — avoids empty Active before match lands.
    final bloc = rootCtx.read<TaskBloc>();
    late final StreamSubscription sub;
    sub = bloc.stream.listen((s) {
      if (s is TaskAccepted && s.task.id == task.id) {
        sub.cancel();
        if (rootCtx.mounted) {
          rootCtx.go('/job/${s.task.id}/active');
        }
      } else if (s is TaskFailure) {
        sub.cancel();
        if (rootCtx.mounted) {
          ScaffoldMessenger.of(rootCtx).showSnackBar(
            SnackBar(
              content: Text(s.message),
              backgroundColor: AppColors.errorColor,
            ),
          );
        }
      }
    });
    bloc.add(TaskAccept(taskId: task.id, helperId: helperId));
  }

  Future<void> _showPillarCMatch(
    BuildContext ctx,
    Map<String, dynamic> ranking,
  ) async {
    final candidates = ranking['candidates'] as List? ?? [];
    final top = candidates.isNotEmpty ? candidates.first as Map : null;
    final selectedName =
        ranking['selected_helper_name']?.toString() ?? top?['name']?.toString();
    final nearestDep = ranking['nearest_deprioritized'] == true;
    final explanation = ranking['explanation']?.toString() ?? '';
    final tools = (ranking['tool_trace'] as List?) ?? const [];

    await showDialog<void>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Explain my match'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                nearestDep
                    ? 'Nearest helper deprioritized (disputes / trust). Selected: ${selectedName ?? '—'}'
                    : 'Selected: ${selectedName ?? '—'}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: nearestDep
                      ? AppColors.warningColor
                      : AppColors.successColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (explanation.isNotEmpty) ...[
                const Gap(10),
                Text(explanation, style: AppTextStyles.bodySmall),
              ],
              if (candidates.isNotEmpty) ...[
                const Gap(10),
                Text('Why they fit', style: AppTextStyles.headingSmall),
                const Gap(4),
                ...candidates.take(4).map((c) {
                  final m = c as Map;
                  final reasons = (m['reasons'] as List?)
                          ?.map((e) => e.toString())
                          .join(' · ') ??
                      '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${m['name']} · ${m['distanceKm']} km · score ${m['score']}'
                      '${m['trust_tier'] != null ? ' · ${m['trust_tier']}' : ''}'
                      '${m['dispute_count'] != null ? ' · disputes ${m['dispute_count']}' : ''}'
                      '${reasons.isNotEmpty ? '\n$reasons' : ''}',
                      style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
                    ),
                  );
                }),
              ],
              if (tools.isNotEmpty) ...[
                const Gap(8),
                Text(
                  'Grounded on: ${tools.map((t) => (t as Map)['name']).join(' → ')}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Accept & continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendQuote(
    BuildContext sheetCtx,
    BuildContext rootCtx,
    Task task,
    String helperId,
  ) async {
    final amountCtrl = TextEditingController(
      text: task.totalAmount.toStringAsFixed(0),
    );
    final msgCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: rootCtx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Send job quote'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount (LKR)'),
            ),
            const Gap(10),
            TextField(
              controller: msgCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Message (optional)',
                hintText: 'No cash courier / illegal work',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (ok != true || !rootCtx.mounted) return;
    final amount = double.tryParse(amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(rootCtx).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }
    try {
      await rootCtx.read<TrustRepository>().submitQuote(
            taskId: task.id,
            helperId: helperId,
            amountLkr: amount,
            message: msgCtrl.text.trim().isEmpty ? null : msgCtrl.text.trim(),
            estimatedHours: task.estimatedHours,
          );
      if (!sheetCtx.mounted || !rootCtx.mounted) return;
      Navigator.pop(sheetCtx);
      ScaffoldMessenger.of(rootCtx).showSnackBar(
        const SnackBar(
          content: Text('Quote sent to the client'),
          backgroundColor: AppColors.successColor,
        ),
      );
    } catch (e) {
      if (!rootCtx.mounted) return;
      ScaffoldMessenger.of(rootCtx).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const Gap(4),
          Text(label, style: AppTextStyles.bodySmall.copyWith(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}

class _EarningsRow extends StatelessWidget {
  const _EarningsRow({
    required this.label,
    required this.value,
    this.isTotal = false,
    this.color,
  });
  final String label;
  final String value;
  final bool isTotal;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: isTotal
                ? AppTextStyles.headingSmall
                : AppTextStyles.bodyMedium,
          ),
          Text(
            value,
            style: (isTotal ? AppTextStyles.headingSmall : AppTextStyles.bodyMedium)
                .copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _MapView extends StatelessWidget {
  const _MapView({required this.tasks});
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const Center(
        child: Text('No tasks to display on map.'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final t = tasks[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.helperAccent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_on_rounded,
                    color: AppColors.helperAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title,
                        style: AppTextStyles.headingSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      t.locationLabel ?? 'Lat ${t.location.latitude.toStringAsFixed(3)}, '
                          'Lon ${t.location.longitude.toStringAsFixed(3)}',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                AppConfig.money(t.totalAmount),
                style: AppTextStyles.headingSmall.copyWith(
                    color: AppColors.helperAccent),
              ),
            ],
          ),
        );
      },
    );
  }
}
