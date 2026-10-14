import 'package:hyperlocal/ui/_shared/category_icon.dart';
import 'package:hyperlocal/ui/_shared/empty_state_widget.dart';
import 'package:hyperlocal/ui/_shared/zivo_section.dart';
import 'package:hyperlocal/ui/_shared/helper_job_search.dart';
import 'package:geolocator/geolocator.dart';
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
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/ui/_shared/task_photo_gallery.dart';
import 'package:hyperlocal/ui/_shared/mode_cover_banner.dart';
import 'package:hyperlocal/blocs/mode/mode_cubit.dart';

/// Helper Home — Feed of nearby human tasks to pick up.
class HelperHomeScreen extends StatefulWidget {
  const HelperHomeScreen({super.key});

  @override
  State<HelperHomeScreen> createState() => _HelperHomeScreenState();
}

class _HelperHomeScreenState extends State<HelperHomeScreen> {
  TaskCategory? _selectedCategory;
  String _searchQuery = '';
  bool _presenceOn = false;
  bool _presenceBusy = false;
  List<Map<String, dynamic>> _batchStops = const [];
  int _vouchCount = 0;
  int _vouchThreshold = 3;
  bool _neighborVouched = false;

  @override
  void initState() {
    super.initState();
    context.read<TaskBloc>()
      ..add(TaskFetchNearbyTasks())
      ..add(TaskSubscribeToFeed());
    _refreshBatchRoute();
    _refreshTrust();
  }

  Future<void> _refreshTrust() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    try {
      final card = await context.read<TaskRepository>().helperTrust(
        auth.profile.id,
      );
      if (!mounted) return;
      setState(() {
        _vouchCount = (card['vouch_count'] as num?)?.toInt() ?? 0;
        _vouchThreshold = (card['vouch_threshold'] as num?)?.toInt() ?? 3;
        _neighborVouched = card['neighbor_vouched'] == true;
      });
    } catch (_) {
      /* demo helpers use seeded badge via live list */
    }
  }

  Future<void> _refreshBatchRoute() async {
    try {
      final res = await context.read<TaskRepository>().helperBatchRoute();
      if (!mounted) return;
      final tasks = (res['active_tasks'] as List?) ?? const [];
      setState(() {
        _batchStops = tasks
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (_) {
      /* optional */
    }
  }

  Future<void> _togglePresence(bool on) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign in to go Available')));
      return;
    }
    setState(() => _presenceBusy = true);
    try {
      Position? position;
      if (on) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied)
          permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          throw Exception('Allow location access to receive nearby requests.');
        }
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 12),
        );
      }
      if (!mounted) return;
      await context.read<TaskRepository>().setHelperPresence(
        available: on,
        lat: position?.latitude,
        lon: position?.longitude,
      );
      if (!mounted) return;
      setState(() => _presenceOn = on);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            on
                ? 'You are now available for nearby requests'
                : 'You are now unavailable',
          ),
          backgroundColor: AppColors.helperAccent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.errorColor),
      );
    } finally {
      if (mounted) setState(() => _presenceBusy = false);
    }
  }

  Color _catColor(TaskCategory cat) {
    switch (cat) {
      case TaskCategory.queueStanding:
        return AppColors.catQueue;
      case TaskCategory.laundry:
        return AppColors.catLaundry;
      case TaskCategory.groceryRun:
        return AppColors.catGrocery;
      case TaskCategory.homeCleaning:
        return AppColors.catCleaning;
      case TaskCategory.homeCooking:
        return AppColors.catCooking;
      case TaskCategory.movingHelp:
        return AppColors.catMoving;
      case TaskCategory.tutoring:
        return AppColors.catTutoring;
      case TaskCategory.techHelp:
        return AppColors.catTech;
      case TaskCategory.petCare:
        return AppColors.catPetCare;
      case TaskCategory.tailoring:
        return AppColors.catTailoring;
      case TaskCategory.driver:
        return AppColors.catDriver;
      case TaskCategory.errandRun:
        return AppColors.catErrand;
      case TaskCategory.gardening:
        return AppColors.catGarden;
      case TaskCategory.documentWork:
        return AppColors.catDocument;
      case TaskCategory.hospitalCompanion:
        return AppColors.catHospital;
      case TaskCategory.babysitting:
        return AppColors.catBabysit;
      case TaskCategory.elderCare:
        return AppColors.catElderCare;
      case TaskCategory.eventHelp:
        return AppColors.catEvent;
      case TaskCategory.photography:
        return AppColors.catPhoto;
      case TaskCategory.homeRepair:
        return AppColors.catRepair;
      case TaskCategory.other:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TaskBloc, TaskState>(
      listenWhen: (prev, next) => next is TaskAccepted || next is TaskFailure,
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
            SliverToBoxAdapter(
              child: ModeCoverBanner(
                isHelper: true,
                height: 200,
                searchHint: 'Search jobs near you',
                onSearchTap: _searchJobs,
                onModeTap: () {
                  final mode = context.read<ModeCubit>();
                  if (mode.state is! ModeToggling) mode.toggleMode();
                },
                trailing: Material(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => context.go(AppRoutes.account),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.person_outline, size: 18),
                    ),
                  ),
                ),
              ),
            ),
            _buildPresenceCard(),
            _buildEarningsBar(),
            _buildQuickActions(),
            _buildStreetRouteCard(),
            _buildFilterRow(),
            _buildFeedTitle(),
            _buildFeed(),
            const SliverToBoxAdapter(child: Gap(100)),
          ],
        ),
      ),
    );
  }

  Widget _buildPresenceCard() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  (_presenceOn ? AppColors.helperAccent : AppColors.borderColor)
                      .withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _presenceOn ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                color: _presenceOn
                    ? AppColors.helperAccent
                    : AppColors.textMuted,
              ),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your availability',
                      style: AppTextStyles.headingSmall.copyWith(fontSize: 13),
                    ),
                    Text(
                      _presenceOn
                          ? 'Available for nearby requests'
                          : 'Go available when you are ready to work',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const Gap(4),
                    Text(
                      _neighborVouched
                          ? 'Neighbor-Vouched · inside-home unlocked'
                          : 'Vouches $_vouchCount/$_vouchThreshold · inside-home locked',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: _neighborVouched
                            ? AppColors.helperAccent
                            : AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _presenceOn,
                onChanged: _presenceBusy ? null : _togglePresence,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStreetRouteCard() {
    if (_batchStops.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.helperAccent.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Street route · ${_batchStops.length} stop${_batchStops.length == 1 ? '' : 's'}',
                style: AppTextStyles.headingSmall.copyWith(fontSize: 13),
              ),
              const Gap(4),
              Text(
                'Stay on one block — stack micro-tasks without travel',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
              const Gap(8),
              for (var i = 0; i < _batchStops.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${i + 1}. ${_batchStops[i]['title'] ?? 'Stop'}',
                    style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEarningsBar() {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final profile = state is AuthAuthenticated ? state.profile : null;
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.borderColor),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.helperAccent.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _EarningStat(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Total Earned',
                    value: AppConfig.money(profile?.helperEarnings ?? 0.0),
                  ),
                  _Divider(),
                  _EarningStat(
                    icon: Icons.task_alt,
                    label: 'Jobs Done',
                    value: '${profile?.totalTasksHelped ?? 0}',
                  ),
                  _Divider(),
                  _EarningStat(
                    icon: Icons.star_outline,
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

  Future<void> _searchJobs() async {
    final tasks = context.read<TaskBloc>().peekNearbyTasks();
    final auth = context.read<AuthBloc>().state;
    final visible = tasks
        .where(
          (task) =>
              auth is! AuthAuthenticated || task.clientId != auth.profile.id,
        )
        .toList();
    final query = await showSearch<String?>(
      context: context,
      delegate: HelperJobSearch(visible, initialQuery: _searchQuery),
    );
    if (!mounted || query == null) return;
    setState(() {
      _searchQuery = query;
      _selectedCategory = null;
    });
  }

  Widget _buildQuickActions() => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              final auth = context.read<AuthBloc>().state;
              if (auth is! AuthAuthenticated) return;
              final task = await context
                  .read<TaskBloc>()
                  .resolveHelperActiveTask(helperId: auth.profile.id);
              if (!mounted) return;
              if (task != null) {
                context.go('/job/${task.id}/active');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'No active job yet. Browse the opportunities below.',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.work_outline_rounded, size: 18),
            label: const Text('Active job'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go(AppRoutes.wallet),
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: const Text('Earnings'),
          ),
        ],
      ),
    ),
  );

  Widget _buildFilterRow() => SliverToBoxAdapter(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                label: Text(_searchQuery),
                onDeleted: () => setState(() => _searchQuery = ''),
              ),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All jobs'),
                  selected: _selectedCategory == null,
                  onSelected: (_) => setState(() => _selectedCategory = null),
                ),
              ),
              for (final category in TaskCategory.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(CategoryIcon.iconFor(category), size: 16),
                    label: Text(category.displayName),
                    selected: _selectedCategory == category,
                    onSelected: (_) =>
                        setState(() => _selectedCategory = category),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildFeedTitle() => SliverToBoxAdapter(
    child: ZivoSection(
      title: 'Find your next job',
      subtitle: 'Browse requests and choose what suits you',
      action: 'Refresh',
      onAction: () => context.read<TaskBloc>().add(TaskFetchNearbyTasks()),
    ),
  );

  Widget _buildFeed() {
    return BlocBuilder<TaskBloc, TaskState>(
      builder: (context, state) {
        if (state is TaskLoading) {
          return const SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.helperAccent,
                strokeWidth: 2,
              ),
            ),
          );
        }

        var tasks = state is TaskNearbyLoaded
            ? state.tasks
            : context.read<TaskBloc>().peekNearbyTasks();
        final me = context.read<AuthBloc>().state;
        if (me is AuthAuthenticated) {
          tasks = tasks.where((t) => t.clientId != me.profile.id).toList();
        }
        tasks = tasks
            .where(
              (task) =>
                  (_selectedCategory == null ||
                      task.category == _selectedCategory) &&
                  HelperJobSearch.matches(task, _searchQuery),
            )
            .toList();
        if (tasks.isEmpty &&
            (_selectedCategory != null || _searchQuery.isNotEmpty)) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: EmptyStateWidget(
                icon: Icons.search_off_rounded,
                title: 'No matching jobs',
                subtitle: 'Try another service or clear your filters.',
                color: AppColors.helperAccent,
                actionLabel: 'Clear filters',
                onAction: () => setState(() {
                  _selectedCategory = null;
                  _searchQuery = '';
                }),
              ),
            ),
          );
        }

        if (tasks.isEmpty) {
          final auth = context.read<AuthBloc>().state;
          final helperId = auth is AuthAuthenticated ? auth.profile.id : null;
          final active = context.read<TaskBloc>().getActiveTaskForHelper(
            helperId: helperId,
          );
          return SliverFillRemaining(
            hasScrollBody: false,
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
      case TaskCategory.queueStanding:
        return AppColors.catQueue;
      case TaskCategory.laundry:
        return AppColors.catLaundry;
      case TaskCategory.groceryRun:
        return AppColors.catGrocery;
      case TaskCategory.homeCleaning:
        return AppColors.catCleaning;
      case TaskCategory.homeCooking:
        return AppColors.catCooking;
      case TaskCategory.movingHelp:
        return AppColors.catMoving;
      case TaskCategory.tutoring:
        return AppColors.catTutoring;
      case TaskCategory.techHelp:
        return AppColors.catTech;
      case TaskCategory.petCare:
        return AppColors.catPetCare;
      case TaskCategory.tailoring:
        return AppColors.catTailoring;
      case TaskCategory.driver:
        return AppColors.catDriver;
      case TaskCategory.errandRun:
        return AppColors.catErrand;
      case TaskCategory.gardening:
        return AppColors.catGarden;
      case TaskCategory.documentWork:
        return AppColors.catDocument;
      case TaskCategory.hospitalCompanion:
        return AppColors.catHospital;
      case TaskCategory.babysitting:
        return AppColors.catBabysit;
      case TaskCategory.elderCare:
        return AppColors.catElderCare;
      case TaskCategory.eventHelp:
        return AppColors.catEvent;
      case TaskCategory.photography:
        return AppColors.catPhoto;
      case TaskCategory.homeRepair:
        return AppColors.catRepair;
      case TaskCategory.other:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _catColor(task.category);
    return _JobCard(task: task, index: index, color: color);
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.task,
    required this.index,
    required this.color,
  });
  final Task task;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CategoryIconBadge(task.category, size: 48),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.category.displayName,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.helperAccent,
                        ),
                      ),
                      const Gap(3),
                      Text(
                        task.title,
                        style: AppTextStyles.headingSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
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
              const Gap(12),
              TaskPhotoGallery(
                photoUrls: task.photoUrls,
                height: 80,
                label: 'Client photos',
              ),
            ],
            const Gap(12),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                Text(
                  '${task.estimatedHours}h estimated',
                  style: AppTextStyles.bodySmall,
                ),
                if (task.locationLabel != null)
                  Text(
                    task.locationLabel!,
                    style: AppTextStyles.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            const Divider(height: 28),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 20,
              runSpacing: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your earnings', style: AppTextStyles.bodySmall),
                    Text(
                      AppConfig.money(task.totalAmount * .9),
                      style: AppTextStyles.headingMedium,
                    ),
                  ],
                ),
                FilledButton(
                  onPressed: () {
                    final auth = context.read<AuthBloc>().state;
                    if (auth is! AuthAuthenticated) return;
                    if (task.clientId == auth.profile.id) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('You cannot accept a task you posted.'),
                        ),
                      );
                      return;
                    }
                    context.read<TaskBloc>().add(
                      TaskAccept(taskId: task.id, helperId: auth.profile.id),
                    );
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(112, 48),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Accept job'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _EarningStat extends StatelessWidget {
  const _EarningStat({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.textPrimary),
          const Gap(4),
          Text(
            value,
            style: AppTextStyles.headingSmall.copyWith(
              color: AppColors.textPrimary,
              fontSize: 15,
            ),
          ),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: AppColors.textPrimary.withOpacity(0.15),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({this.hasActiveJob = false, this.onOpenActive});
  final bool hasActiveJob;
  final VoidCallback? onOpenActive;

  @override
  Widget build(BuildContext context) => EmptyStateWidget(
    icon: hasActiveJob ? Icons.work_outline_rounded : Icons.explore_outlined,
    title: hasActiveJob ? 'Your job is ready' : 'No nearby jobs right now',
    subtitle: hasActiveJob ? 'Continue your accepted job from the Active tab.' : 'New requests will appear here. Check again soon or refresh the list.',
    color: AppColors.helperAccent,
    actionLabel: hasActiveJob ? 'Open active job' : 'Refresh jobs',
    onAction: hasActiveJob
        ? onOpenActive
        : () => context.read<TaskBloc>().add(TaskFetchNearbyTasks()),
  );
}
