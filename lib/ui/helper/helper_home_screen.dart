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
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/utils/quick_position.dart';

import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/ui/_shared/task_photo_gallery.dart';
import 'package:hyperlocal/ui/_shared/mode_cover_banner.dart';
import 'package:hyperlocal/ui/_shared/cover_top_bar_actions.dart';
import 'package:hyperlocal/ui/_shared/horizontal_inset_scroller.dart';
import 'package:hyperlocal/ui/_shared/task_journey_sheet.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';

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

    final previous = _presenceOn;
    // Optimistic flip — UI responds instantly; GPS/API catch up in background.
    setState(() {
      _presenceOn = on;
      _presenceBusy = true;
    });

    try {
      Position? position;
      if (on) {
        position = await quickPosition(
          deniedMessage:
              'Allow location access to receive nearby requests.',
        );
      }
      if (!mounted) return;
      await context.read<TaskRepository>().setHelperPresence(
        available: on,
        lat: position?.latitude,
        lon: position?.longitude,
      );
      if (!mounted) return;
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
      setState(() => _presenceOn = previous);
      final msg = '$e'
          .replaceFirst('Exception: ', '')
          .replaceFirst('Unsupported operation: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.errorColor,
        ),
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
      case TaskCategory.phoneCheckIn:
      case TaskCategory.readingAloud:
      case TaskCategory.remoteTutoring:
        return AppColors.catTutoring;
      case TaskCategory.sightedAssist:
        return AppColors.catTech;
      case TaskCategory.phoneCheckIn:
      case TaskCategory.readingAloud:
      case TaskCategory.remoteTutoring:
        return AppColors.catTutoring;
      case TaskCategory.sightedAssist:
        return AppColors.catTech;
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
        context.push('/job/${state.task.id}/active');
      },
      child: Scaffold(
        backgroundColor: ZivoPalette.of(context).canvas,
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ModeCoverBanner(
                isHelper: true,
                height: 200,
                searchHint: context.watch<LocaleCubit>().t('helper.searchHint'),
                onSearchTap: _searchJobs,
                // Same top bar as client: wallet + account on desktop, wallet on mobile.
                trailing: CoverTopBarActions(
                  showAccount: CoverTopBarActions.isDesktop(context),
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
            SliverToBoxAdapter(
              child: SizedBox(
                height: 28 + MediaQuery.paddingOf(context).bottom + 72,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresenceCard() {
    final palette = ZivoPalette.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (_presenceOn ? palette.accent : palette.border)
                  .withValues(alpha: _presenceOn ? 0.7 : 1),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _presenceOn ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                color: _presenceOn ? palette.accent : palette.textMuted,
              ),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.watch<LocaleCubit>().t('helper.availability'),
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    Text(
                      _presenceOn
                          ? context.watch<LocaleCubit>().t('helper.availOn')
                          : context.watch<LocaleCubit>().t('helper.availOff'),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const Gap(2),
                    Text(
                      _neighborVouched
                          ? 'Neighbor-Vouched · inside-home unlocked'
                          : 'Vouches $_vouchCount/$_vouchThreshold · inside-home locked',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: _neighborVouched
                            ? palette.accent
                            : palette.textMuted,
                        fontSize: 11,
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
        child: Builder(
          builder: (context) {
            final palette = ZivoPalette.of(context);
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: palette.accent.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Street route · ${_batchStops.length} stop${_batchStops.length == 1 ? '' : 's'}',
                    style: AppTextStyles.headingSmall.copyWith(
                      fontSize: 13,
                      color: palette.textPrimary,
                    ),
                  ),
                  const Gap(4),
                  Text(
                    'Stay on one block — stack micro-tasks without travel',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const Gap(8),
                  for (var i = 0; i < _batchStops.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${i + 1}. ${_batchStops[i]['title'] ?? 'Stop'}',
                        style: AppTextStyles.bodySmall.copyWith(
                          fontSize: 12,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEarningsBar() {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final profile = state is AuthAuthenticated ? state.profile : null;
        final palette = ZivoPalette.of(context);
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: palette.card,
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.helperAccent.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
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

  Widget _buildQuickActions() {
    final auth = context.watch<AuthBloc>().state;
    final helperId = auth is AuthAuthenticated ? auth.profile.id : null;
    final active = context.watch<TaskBloc>().getActiveTaskForHelper(
      helperId: helperId,
    );
    final palette = ZivoPalette.of(context);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (active != null) ...[
              Text(
                'Active job',
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: palette.textMuted,
                ),
              ),
              const Gap(6),
              TaskNameChip(task: active, isHelper: true),
              const Gap(8),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.go(AppRoutes.wallet),
                icon: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 16,
                  color: palette.textSecondary,
                ),
                label: Text(
                  'Earnings',
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    final l = context.watch<LocaleCubit>();
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  label: Text(
                    _searchQuery,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onDeleted: () => setState(() => _searchQuery = ''),
                ),
              ),
            ),
          HorizontalInsetScroller(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
            children: [
              ChoiceChip(
                label: Text(l.t('helper.allJobs')),
                selected: _selectedCategory == null,
                onSelected: (_) => setState(() => _selectedCategory = null),
              ),
              for (final category in TaskCategory.values)
                ChoiceChip(
                  avatar: Icon(CategoryIcon.iconFor(category), size: 16),
                  label: Text(
                    l.category(category),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: _selectedCategory == category,
                  onSelected: (_) =>
                      setState(() => _selectedCategory = category),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeedTitle() {
    final l = context.watch<LocaleCubit>();
    return SliverToBoxAdapter(
      child: ZivoSection(
        title: l.t('helper.findJob'),
        subtitle: '',
        action: l.t('helper.refresh'),
        onAction: () => context.read<TaskBloc>().add(TaskFetchNearbyTasks()),
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
                  : () => context.push('/job/${active.id}/active'),
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
      case TaskCategory.phoneCheckIn:
      case TaskCategory.readingAloud:
      case TaskCategory.remoteTutoring:
        return AppColors.catTutoring;
      case TaskCategory.sightedAssist:
        return AppColors.catTech;
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

  String _cleanDescription(String raw) {
    var t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    final m = RegExp(r'^(.{12,90}?)\1+').firstMatch(t);
    if (m != null) t = m.group(1)!.trim();
    if (t.length > 100) t = '${t.substring(0, 97)}…';
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final desc = _cleanDescription(task.description);
    final palette = ZivoPalette.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: CategoryIcon(task.category, size: 14),
                        ),
                        const Gap(8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.category(task.category),
                                style: AppTextStyles.bodySmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: palette.textMuted,
                                  fontSize: 10,
                                  height: 1.1,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                task.title,
                                style: AppTextStyles.headingSmall.copyWith(
                                  fontSize: 13.5,
                                  height: 1.15,
                                  fontWeight: FontWeight.w700,
                                  color: palette.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const Gap(6),
                      Text(
                        desc,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.textSecondary,
                          fontSize: 11.5,
                          height: 1.25,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (task.photoUrls.isNotEmpty) ...[
                      const Gap(6),
                      TaskPhotoGallery(
                        photoUrls: task.photoUrls,
                        height: 52,
                        label: 'Photos',
                      ),
                    ],
                    const Gap(8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            [
                              AppConfig.money(task.totalAmount * .9),
                              '${task.estimatedHours}h',
                              if (task.locationLabel != null)
                                task.locationLabel!,
                            ].join('  ·  '),
                            style: AppTextStyles.moneyMeta.copyWith(
                              color: color,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Gap(8),
                        FilledButton(
                          onPressed: () {
                            final auth = context.read<AuthBloc>().state;
                            if (auth is! AuthAuthenticated) return;
                            if (task.clientId == auth.profile.id) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'You cannot accept a task you posted.',
                                  ),
                                ),
                              );
                              return;
                            }
                            context.read<TaskBloc>().add(
                                  TaskAccept(
                                    taskId: task.id,
                                    helperId: auth.profile.id,
                                  ),
                                );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.accent,
                            foregroundColor: palette.onAccent,
                            // No max width — Tamil/Sinhala "Accept" must fit one line.
                            minimumSize: const Size(0, 34),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                          child: Text(
                            l.t('helper.accept'),
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 40 * index))
        .fadeIn(duration: 240.ms);
  }
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
    final palette = ZivoPalette.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: palette.textSecondary),
          const Gap(4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: AppTextStyles.moneyStat.copyWith(
                color: palette.textPrimary,
              ),
            ),
          ),
          const Gap(2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTextStyles.moneyStatLabel.copyWith(
              color: palette.textMuted,
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
      color: ZivoPalette.of(context).border,
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
