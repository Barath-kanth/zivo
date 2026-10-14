import 'package:hyperlocal/ui/_shared/category_icon.dart';
import 'dart:async';
import 'package:hyperlocal/ui/_shared/zivo_section.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hyperlocal/ui/_shared/service_search.dart';

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
import 'package:hyperlocal/core/utils/auth_gate.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/models/task_status.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/ui/_shared/zivo_logo.dart';
import 'package:hyperlocal/ui/_shared/task_status_badge.dart';
import 'package:hyperlocal/ui/_shared/mode_cover_banner.dart';
import 'package:hyperlocal/ui/_shared/trust_review_sheet.dart';
import 'package:hyperlocal/ui/_shared/a11y_widgets.dart';
import 'package:hyperlocal/blocs/mode/mode_cubit.dart';

enum ClientHomePane {
  /// Full home (mobile single column, or desktop services + rail).
  full,

  /// Dedicated task history with the existing chat, OTP and dispute controls.
  tasksOnly,

  /// Desktop services column only — shell owns the activity rail.
  servicesOnly,

  /// Desktop activity rail only — stays mounted across shell destinations.
  railOnly,
}

/// Client Home — Uber-style service marketplace for human tasks.
class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({
    super.key,
    this.pane = ClientHomePane.full,
    this.forceDesktopChrome = false,
  });

  final ClientHomePane pane;

  /// Match shell sidebar (≥1100px) even when the content pane is <900px wide.
  final bool forceDesktopChrome;

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  Timer? _refreshTimer;
  List<Map<String, dynamic>> _streetBatches = const [];
  List<Map<String, dynamic>> _liveHelpers = const [];
  bool _helperMapExpanded = false;
  Position? _nearbyPosition;
  bool _locating = false;
  String _taskFilter = 'Active';

  @override
  void initState() {
    super.initState();
    _refreshClientTasks(silent: false);

    // Quiet poll only while a job needs Start/End OTP (no full-page flash).
    _refreshTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      final bloc = context.read<TaskBloc>();
      final tasks = bloc.peekClientTasks();
      final needsOtp = tasks.any(
        (t) =>
            t.status == TaskStatus.matched ||
            t.status == TaskStatus.inProgress,
      );
      if (needsOtp) _refreshClientTasks(silent: true);
      _refreshStreetBatches();
      _refreshLiveHelpers();
    });
  }

  static String _cleanHelperName(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Helper';
    return raw
        .replaceAll(RegExp(r'\s*\(verified\)', caseSensitive: false), '')
        .trim();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStreetBatches() async {
    if (_nearbyPosition == null) return;
    try {
      final res = await context.read<TaskRepository>().listStreetBatches(
            lat: _nearbyPosition!.latitude,
            lon: _nearbyPosition!.longitude,
          );
      if (!mounted) return;
      final offers = (res['offers'] as List?) ?? const [];
      setState(() {
        _streetBatches = offers
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (_) {
      /* ignore — banner optional */
    }
  }

  Future<void> _refreshLiveHelpers() async {
    if (_nearbyPosition == null) return;
    try {
      final res = await context.read<TaskRepository>().listLiveHelpers(
            lat: _nearbyPosition!.latitude,
            lon: _nearbyPosition!.longitude,
          );
      if (!mounted) return;
      final helpers = (res['helpers'] as List?) ?? const [];
      setState(() {
        _liveHelpers = helpers
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (_) {
      /* optional */
    }
  }

  void _refreshClientTasks({bool silent = false}) {
    final auth = context.read<AuthBloc>().state;
    if (auth is AuthAuthenticated) {
      context.read<TaskBloc>().add(
            TaskFetchClientTasks(auth.profile.id, silent: silent),
          );
    }
  }

  // Category color mapping
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

  Widget _buildServicesColumn() {
    return CustomScrollView(
      key: const PageStorageKey('client-desktop-services'),
      slivers: [
        _buildCoverHeader(),
        _buildSectionTitle('What do you need help with?'),
        _buildCategoryGrid(),
        _buildWalletStrip(),
        const SliverToBoxAdapter(child: Gap(100)),
      ],
    );
  }

  Widget _buildCoverHeader() {
    return SliverToBoxAdapter(
      child: ModeCoverBanner(
        isHelper: false,
        height: 190,
        searchHint: 'What do you need help with?',
        onSearchTap: _searchServices,
        onModeTap: () {
          final mode = context.read<ModeCubit>();
          if (mode.state is! ModeToggling) mode.toggleMode();
        },
        trailing: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            final profile =
                state is AuthAuthenticated ? state.profile : null;
            final initial = profile?.displayInitial ?? '?';
            final avatarUrl = profile?.avatarUrl;
            final hasAvatar =
                avatarUrl != null && avatarUrl.startsWith('http');
            return Material(
              color: Colors.white.withValues(alpha: 0.92),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => context.go(AppRoutes.account),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.white,
                  backgroundImage:
                      hasAvatar ? NetworkImage(avatarUrl) : null,
                  child: hasAvatar
                      ? null
                      : Text(
                          initial,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: Colors.black,
                          ),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWalletStrip() {
    return SliverToBoxAdapter(
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          final profile = state is AuthAuthenticated ? state.profile : null;
          final wallet = profile?.walletBalance ?? 0.0;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const ZivoLogo(size: 28),
                  const Gap(10),
                  Expanded(
                    child: Text(
                      AppConfig.money(wallet),
                      style: AppTextStyles.moneyMedium.copyWith(fontSize: 20),
                    ),
                  ),
                  _miniAction(
                    icon: Icons.north_east_rounded,
                    label: 'Wallet',
                    onTap: () => context.go(AppRoutes.wallet),
                  ),

                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _miniAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: Colors.black),
          ),
          const Gap(2),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityRail() {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
        border: Border(left: BorderSide(color: AppColors.borderColor)),
      ),
      child: SafeArea(
        child: CustomScrollView(
          key: const PageStorageKey('client-desktop-activity'),
          slivers: [
            _buildSectionTitle('Your active tasks'),
            _buildMyTasks(),
            _buildSectionTitle('Around your neighbourhood'),
            _buildLocationControl(),
            _buildInstantDispatchCard(),
            _buildStreetBatchCard(),
            _buildNeighborVouchCard(),
            _buildNearbyHelpersMap(),
            const SliverToBoxAdapter(child: Gap(100)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pane == ClientHomePane.tasksOnly) {
      return Scaffold(
        appBar: AppBar(title: const Text('My tasks'), actions: [
          IconButton(tooltip: 'Refresh tasks', onPressed: () => _refreshClientTasks(),
            icon: const Icon(Icons.refresh_rounded)),
          TextButton(onPressed: _searchServices, child: const Text('New task')),
        ]),
        body: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final filter in ['Active', 'Completed', 'All'])
                ChoiceChip(label: Text(filter), selected: _taskFilter == filter,
                  onSelected: (_) => setState(() => _taskFilter = filter)),
            ]),
          )),
          _buildMyTasks(),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ]),
      );
    }
    if (widget.pane == ClientHomePane.railOnly) {
      return ColoredBox(
        color: AppColors.surfaceDark,
        child: _buildActivityRail(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop =
              widget.forceDesktopChrome || constraints.maxWidth >= 900;

          if (widget.pane == ClientHomePane.servicesOnly) {
            return _buildServicesColumn();
          }

          if (desktop) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildServicesColumn()),
                _buildActivityRail(),
              ],
            );
          }

          return CustomScrollView(
            key: const PageStorageKey('client-mobile-home'),
            slivers: [
              _buildCoverHeader(),
              _buildSectionTitle('Everyday help, sorted'),
              _buildCategoryGrid(compact: true),
              _buildSectionTitle('Your active tasks'),
              _buildMyTasks(),
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextButton(onPressed: () => context.go(AppRoutes.myTasks),
                  child: const Text('View all tasks')),
              )),
              _buildWalletStrip(),
              _buildSectionTitle('Around your neighbourhood'),
              _buildLocationControl(),
              _buildInstantDispatchCard(),
              _buildStreetBatchCard(),
              _buildNeighborVouchCard(),
              _buildNearbyHelpersMap(),
              const SliverToBoxAdapter(child: Gap(100)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(color: AppColors.backgroundDark),
        child: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    final profile =
                        state is AuthAuthenticated ? state.profile : null;
                    final name = profile?.displayShort ?? 'there';
                    final initial = profile?.displayInitial ?? '?';
                    final wallet = profile?.walletBalance ?? 0.0;
                    final avatarUrl = profile?.avatarUrl;
                    final hasAvatar = avatarUrl != null &&
                        avatarUrl.startsWith('http');

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Brand + account pill
                            Row(
                              children: [
                                const ZivoLogo(
                                  size: 34,
                                  showWordmark: true,
                                  markOnDark: false,
                                  wordmarkColor: AppColors.textPrimary,
                                ),
                                const Spacer(),
                                Material(
                                  color: AppColors.surfaceDark,
                                  borderRadius: BorderRadius.circular(28),
                                  child: InkWell(
                                    onTap: () =>
                                        context.go(AppRoutes.account),
                                    borderRadius: BorderRadius.circular(28),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          6, 5, 12, 5),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor: Colors.white,
                                            backgroundImage: hasAvatar
                                                ? NetworkImage(avatarUrl)
                                                : null,
                                            child: hasAvatar
                                                ? null
                                                : Text(
                                                    initial,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: Colors.black,
                                                    ),
                                                  ),
                                          ),
                                          const Gap(8),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 110),
                                            child: Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          ),
                                          const Gap(2),
                                          Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            size: 18,
                                            color: AppColors.textSecondary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                                .animate()
                                .fadeIn(duration: 400.ms)
                                .slideY(
                                    begin: -0.15, curve: Curves.easeOut),
                            const Gap(28),
                            // Primary service heading
                            Text(
                              'Who can help\nyou today?',
                              textAlign: TextAlign.left,
                              style: AppTextStyles.displayMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontSize: 32,
                                height: 1.15,
                                letterSpacing: -1.2,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                                .animate()
                                .fadeIn(delay: 80.ms, duration: 450.ms)
                                .slideY(
                                    begin: 0.08,
                                    curve: Curves.easeOutCubic),
                            const Gap(12),
                            Text(
                              'Trusted help nearby — queues, chores, care.',
                              textAlign: TextAlign.left,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                            )
                                .animate()
                                .fadeIn(delay: 160.ms, duration: 400.ms),
                            const Gap(24),
                            // Existing account shortcuts
                            Row(
                              children: [
                                Expanded(
                                  child: _headerActionTile(
                                    icon: Icons.handshake_outlined,
                                    label: 'Earn',
                                    sublabel: 'Helper',
                                    accent: AppColors.accent,
                                    onTap: () {
                                      final mode = context.read<ModeCubit>();
                                      if (mode.state is! ModeToggling) {
                                        mode.toggleMode();
                                      }
                                    },
                                  ),
                                ),
                                const Gap(10),
                                Expanded(
                                  child: _headerActionTile(
                                    icon: Icons
                                        .account_balance_wallet_outlined,
                                    label: 'Wallet',
                                    sublabel: AppConfig.money(wallet),
                                    accent: AppColors.accent,
                                    onTap: () =>
                                        context.go(AppRoutes.wallet),
                                  ),
                                ),
                                const Gap(10),
                                Expanded(
                                  child: _headerActionTile(
                                    icon: Icons.person_outline_rounded,
                                    label: 'Account',
                                    sublabel: 'Profile',
                                    accent: AppColors.accent,
                                    onTap: () =>
                                        context.go(AppRoutes.account),
                                  ),
                                ),
                              ],
                            )
                                .animate()
                                .fadeIn(delay: 220.ms, duration: 450.ms)
                                .slideY(
                                    begin: 0.12,
                                    curve: Curves.easeOutCubic),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerActionTile({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.surfaceDark,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
              const Gap(8),
              Text(
                label,
                textAlign: TextAlign.left,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const Gap(2),
              Text(
                sublabel,
                textAlign: TextAlign.left,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: GestureDetector(
          onTap: () async {
            if (!await requireAuth(context, returnTo: AppRoutes.createTask)) {
              return;
            }
            if (!mounted) return;
            if (!await requireVerified(context, returnTo: AppRoutes.createTask)) {
              return;
            }
            if (!mounted) return;
            context.go(AppRoutes.createTask);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderColor),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded,
                    color: AppColors.textMuted, size: 20),
                const Gap(10),
                Expanded(
                  child: Text(
                    'Describe what you need help with…',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Gap(12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Post',
                    style: AppTextStyles.capsLabel.copyWith(
                        color: Colors.white, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08),
      ),
    );
  }

  Widget _buildInstantDispatchCard() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Material(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _runInstantDispatch,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bolt_rounded,
                        color: AppColors.accent),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Find help now',
                          style: AppTextStyles.headingSmall.copyWith(fontSize: 14),
                        ),
                        Text(
                          'Review the price, then request a nearby helper',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _runInstantDispatch() async {
    if (!await requireAuth(context, returnTo: AppRoutes.shell)) return;
    if (!mounted) return;
    if (!await requireVerified(context, returnTo: AppRoutes.shell)) return;
    if (!mounted) return;

    final titleCtrl = TextEditingController(text: 'Quick help nearby');
    final descCtrl = TextEditingController(
      text:
          'Need someone for about 15 minutes at my place — describe the full situation here.',
    );
    final boostCtrl = TextEditingController();
    var urgency = 'urgent';
    var category = 'errandRun';
    var durationMin = 15;
    var travelKm = 0.0;
    var clientBoost = 0;
    Map<String, dynamic>? quote;
    var quoting = false;
    String? descError;
    Timer? debounce;

    final presets = <Map<String, String>>[
      {
        'cat': 'errandRun',
        'label': 'Errand',
        'title': 'Quick help nearby',
        'desc':
            'Need someone for about 15 minutes at my place for a simple neighborhood errand.',
      },
      {
        'cat': 'queueStanding',
        'label': 'Queue',
        'title': 'Hold bakery queue',
        'desc':
            'Stand in the morning bakery queue for me — expect 20–30 minutes wait in the rush.',
      },
      {
        'cat': 'movingHelp',
        'label': 'Heavy',
        'title': 'Carry couch up stairs',
        'desc':
            'Help carry a heavy sofa up two flights of stairs at my apartment right now.',
      },
      {
        'cat': 'gardening',
        'label': 'Plants',
        'title': 'Water my plants',
        'desc':
            'Quick porch plant watering for about five minutes while I am away from home.',
      },
    ];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> refreshQuote() async {
              final desc = descCtrl.text.trim();
              if (desc.length < 20) {
                setLocal(() {
                  descError = 'Description required (min 20 characters)';
                  quote = null;
                  quoting = false;
                });
                return;
              }
              setLocal(() {
                descError = null;
                quoting = true;
              });
              try {
                final q = await context.read<TaskRepository>().priceQuote(
                      title: titleCtrl.text.trim(),
                      description: desc,
                      category: category,
                      lat: 6.9271,
                      lon: 79.8612,
                      durationMinutes: durationMin,
                      urgency: urgency,
                      travelKm: travelKm > 0 ? travelKm : null,
                      destLat: travelKm > 0 ? 6.91 : null,
                      destLon: travelKm > 0 ? 79.87 : null,
                      clientBoostLkr: clientBoost,
                    );
                if (!ctx.mounted) return;
                setLocal(() {
                  quote = q;
                  quoting = false;
                });
              } catch (e) {
                if (ctx.mounted) {
                  setLocal(() {
                    quoting = false;
                    descError = '$e';
                  });
                }
              }
            }

            void scheduleQuote() {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 550), refreshQuote);
            }

            final fairFloor = quote?['gemini_labor_lkr'] ?? quote?['labor_lkr'];
            final total = quote?['labor_lkr'];
            final boost = quote?['client_boost_lkr'] ?? 0;
            final priceNote = quote?['explanation']?.toString();
            final policy = quote?['policy']?.toString();

            if (quote == null && !quoting && descError == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (ctx.mounted) refreshQuote();
              });
            }

            return AlertDialog(
              title: const Text('Find help now'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Task type', style: AppTextStyles.bodySmall),
                    const Gap(6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final p in presets)
                          ChoiceChip(
                            label: Text(p['label']!),
                            selected: category == p['cat'],
                            onSelected: (_) {
                              setLocal(() {
                                category = p['cat']!;
                                titleCtrl.text = p['title']!;
                                descCtrl.text = p['desc']!;
                              });
                              refreshQuote();
                            },
                          ),
                      ],
                    ),
                    const Gap(8),
                    TextField(
                      controller: titleCtrl,
                      decoration:
                          const InputDecoration(labelText: 'What do you need?'),
                      onChanged: (_) => scheduleQuote(),
                    ),
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Full situation (required)',
                        errorText: descError,
                        helperText:
                            'Describe the full situation — we set a fair helper-safe price',
                      ),
                      onChanged: (_) => scheduleQuote(),
                    ),
                    const Gap(10),
                    Text('Duration', style: AppTextStyles.bodySmall),
                    const Gap(6),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final m in [10, 15, 30, 60])
                          ChoiceChip(
                            label: Text(m < 60 ? '${m}m' : '1h'),
                            selected: durationMin == m,
                            onSelected: (_) {
                              setLocal(() => durationMin = m);
                              refreshQuote();
                            },
                          ),
                      ],
                    ),
                    const Gap(10),
                    Text('Travel to destination', style: AppTextStyles.bodySmall),
                    const Gap(6),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final km in [0.0, 0.5, 1.5, 3.0])
                          ChoiceChip(
                            label: Text(km == 0 ? 'On-site' : '${km} km'),
                            selected: travelKm == km,
                            onSelected: (_) {
                              setLocal(() => travelKm = km);
                              refreshQuote();
                            },
                          ),
                      ],
                    ),
                    const Gap(10),
                    Text('Urgency', style: AppTextStyles.bodySmall),
                    const Gap(6),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final u in ['normal', 'soon', 'urgent'])
                          ChoiceChip(
                            label: Text(u),
                            selected: urgency == u,
                            onSelected: (_) {
                              setLocal(() => urgency = u);
                              refreshQuote();
                            },
                          ),
                      ],
                    ),
                    const Gap(12),
                    Text(
                      'Optional tip (cannot go below fair price)',
                      style: AppTextStyles.bodySmall,
                    ),
                    const Gap(6),
                    TextField(
                      controller: boostCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tip LKR (0 = accept fair price)',
                        hintText: 'e.g. 100',
                      ),
                      onChanged: (v) {
                        clientBoost = int.tryParse(v.trim()) ?? 0;
                        if (clientBoost < 0) clientBoost = 0;
                        scheduleQuote();
                      },
                    ),
                    const Gap(14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.25),
                        ),
                      ),
                      child: quoting
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  total == null
                                      ? (descError ?? 'Add a full description')
                                      : 'Pay ${AppConfig.money(num.tryParse('$total') ?? 0)}',
                                  style: AppTextStyles.headingSmall
                                      .copyWith(fontSize: 15),
                                ),
                                if (fairFloor != null) ...[
                                  const Gap(4),
                                  Text(
                                    'Fair floor ${AppConfig.money(num.tryParse('$fairFloor') ?? 0)}'
                                    '${boost != null && boost != 0 ? ' + your tip ${AppConfig.money(num.tryParse('$boost') ?? 0)}' : ''}'
                                    ' · you cannot undercut',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                                if (priceNote != null) ...[
                                  const Gap(4),
                                  Text(
                                    priceNote,
                                    style: AppTextStyles.bodySmall.copyWith(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                                if (policy != null) ...[
                                  const Gap(4),
                                  Text(
                                    policy,
                                    style: AppTextStyles.bodySmall.copyWith(
                                      fontSize: 10,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                TextButton(
                  onPressed: quoting || total == null
                      ? null
                      : () => Navigator.pop(ctx, true),
                  child: const Text('Accept price & dispatch'),
                ),
              ],
            );
          },
        );
      },
    );
    debounce?.cancel();
    if (ok != true || !mounted) {
      titleCtrl.dispose();
      descCtrl.dispose();
      boostCtrl.dispose();
      return;
    }

    try {
      final desc = descCtrl.text.trim();
      if (desc.length < 20) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Description is mandatory (min 20 characters)'),
            backgroundColor: AppColors.errorColor,
          ),
        );
        return;
      }

      final live = await context.read<TaskRepository>().listLiveHelpers(
            lat: 6.9271,
            lon: 79.8612,
          );
      final helpers = live['helpers'] as List? ?? [];
      if (helpers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No porch lights ON nearby — ask a helper to turn Available',
            ),
          ),
        );
        return;
      }

      final result = await context.read<TaskRepository>().instantDispatch(
            title: titleCtrl.text.trim().isEmpty
                ? 'Quick help nearby'
                : titleCtrl.text.trim(),
            description: desc,
            category: category,
            lat: 6.9271,
            lon: 79.8612,
            durationMinutes: durationMin,
            urgency: urgency,
            travelKm: travelKm > 0 ? travelKm : null,
            destLat: travelKm > 0 ? 6.91 : null,
            destLon: travelKm > 0 ? 79.87 : null,
            clientBoostLkr: clientBoost,
          );
      if (!mounted) return;
      final name = result['selected_helper_name']?.toString() ?? 'Helper';
      final pricing = result['pricing'] as Map?;
      final labor = pricing?['labor_lkr'];
      final batch = result['batch'] as Map?;
      final taskMap = result['task'] as Map?;
      final taskId = taskMap?['id']?.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Matched $name · ${labor == null ? '—' : AppConfig.money(num.tryParse('$labor') ?? 0)} locked. '
            '${batch != null ? 'Street batch open for neighbors. ' : ''}'
            'Open tracking to see why they fit.',
          ),
          backgroundColor: AppColors.successColor,
        ),
      );
      final auth = context.read<AuthBloc>().state;
      if (auth is AuthAuthenticated) {
        context.read<TaskBloc>().add(TaskFetchClientTasks(auth.profile.id));
      }
      _refreshStreetBatches();
      if (taskId != null && taskId.isNotEmpty && mounted) {
        context.go('/task/$taskId/track');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanizeError(e)),
          backgroundColor: AppColors.errorColor,
        ),
      );
    } finally {
      titleCtrl.dispose();
      descCtrl.dispose();
      boostCtrl.dispose();
    }
  }

  Widget _buildNeighborVouchCard() {
    final needsVouch = _liveHelpers
        .where((h) => h['neighbor_vouched'] != true)
        .toList();
    if (needsVouch.isEmpty && _liveHelpers.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final target = needsVouch.isNotEmpty
        ? needsVouch.first
        : _liveHelpers.first;
    final name = _cleanHelperName(target['full_name']?.toString());
    final count = target['vouch_count'] ?? 0;
    final threshold = target['vouch_threshold'] ?? 3;
    final badged = target['neighbor_vouched'] == true;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Material(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              if (!badged) {
                _vouchHelper(target);
              } else {
                setState(() => _helperMapExpanded = !_helperMapExpanded);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          badged
                              ? Icons.verified_user_rounded
                              : Icons.handshake_rounded,
                          color: AppColors.accent,
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              badged
                                  ? 'Neighbor-Vouched · $name'
                                  : 'Vouch $name ($count/$threshold)',
                              style: AppTextStyles.headingSmall
                                  .copyWith(fontSize: 14),
                            ),
                            Text(
                              badged
                                  ? 'Unlocked for inside-home micro-tasks'
                                  : 'Stake LKR 200 · 3 local vouches unlock home entry',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!badged)
                        Text(
                          'Vouch',
                          style: AppTextStyles.capsLabel
                              .copyWith(color: AppColors.accent),
                        )
                      else
                        Icon(
                          _helperMapExpanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          color: AppColors.textMuted,
                        ),
                    ],
                  ),
                  if (badged) ...[
                    const Gap(10),
                    InkWell(
                      onTap: () => setState(
                        () => _helperMapExpanded = !_helperMapExpanded,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.map_outlined,
                            size: 16,
                            color: AppColors.helperAccent,
                          ),
                          const Gap(6),
                          Text(
                            _helperMapExpanded
                                ? 'Hide map'
                                : 'Show helpers on map',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.helperAccent,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Availability list; does not imply unverified geographic positions.
  Widget _buildNearbyHelpersMap() {
    if (!_helperMapExpanded) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: Text('Nearby helpers', style: AppTextStyles.headingSmall)),
            IconButton(tooltip: 'Close helpers', icon: const Icon(Icons.close),
              onPressed: () => setState(() => _helperMapExpanded = false)),
          ]),
          if (_nearbyPosition == null)
            const Text('Use your location above to discover helpers in your area.')
          else if (_liveHelpers.isEmpty)
            const Text('No helpers are available nearby right now. You can still post a task.')
          else
            for (final helper in _liveHelpers.take(6))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(backgroundColor: AppColors.brandGreenSoft,
                  child: Icon(Icons.person_outline, color: AppColors.helperAccent)),
                title: Text(_cleanHelperName(helper['full_name']?.toString())),
                subtitle: const Text('Available nearby'),
              ),
        ]),
      )),
    ));
  }

  Future<void> _vouchHelper(Map<String, dynamic> helper) async {
    if (!await requireAuth(context, returnTo: AppRoutes.shell)) return;
    if (!mounted) return;
    if (!await requireVerified(context, returnTo: AppRoutes.shell)) return;
    if (!mounted) return;

    final helperId = helper['id']?.toString();
    if (helperId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neighbor vouch'),
        content: Text(
          'Stake LKR 200 from your wallet to vouch '
          '${helper['full_name'] ?? 'this helper'}. '
          'Three local vouches unlock inside-home tasks for them.',
          style: AppTextStyles.bodySmall,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Stake & vouch')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final result = await context.read<TaskRepository>().vouchNeighbor(
            helperId: helperId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result['explanation'] ?? 'Vouch recorded'}',
          ),
          backgroundColor: AppColors.successColor,
        ),
      );
      _refreshLiveHelpers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  Widget _buildStreetBatchCard() {
    final hasOffer = _streetBatches.isNotEmpty;
    final offer = hasOffer ? _streetBatches.first : null;
    final helper = _cleanHelperName(offer?['helper_name']?.toString());
    final secs = offer?['seconds_left'] ?? 0;
    final price = offer?['sample_labor_lkr'];
    final discount = offer?['discount_pct'] ?? 30;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Material(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: hasOffer && offer != null
                ? () => _joinStreetBatch(offer)
                : () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'No piggyback window yet — Request Instant Dispatch to open one on your block.',
                        ),
                      ),
                    ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasOffer
                      ? AppColors.successColor.withValues(alpha: 0.4)
                      : AppColors.borderColor,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (hasOffer
                              ? AppColors.successColor
                              : AppColors.textMuted)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.route_rounded,
                      color: hasOffer
                          ? AppColors.successColor
                          : AppColors.textMuted,
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasOffer
                              ? 'Street Batch open'
                              : 'Street Batch',
                          style: AppTextStyles.headingSmall
                              .copyWith(fontSize: 14),
                        ),
                        Text(
                          hasOffer
                              ? '$helper on your block · ~$discount% off'
                                  '${price != null ? ' · from ${AppConfig.money(num.tryParse('$price') ?? 0)}' : ''} · ${secs}s left'
                              : 'No piggyback window on your block — Dispatch opens one',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    hasOffer ? 'Join' : 'Wait',
                    style: AppTextStyles.capsLabel.copyWith(
                      color: hasOffer
                          ? AppColors.successColor
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _joinStreetBatch(Map<String, dynamic> offer) async {
    if (!await requireAuth(context, returnTo: AppRoutes.shell)) return;
    if (!mounted) return;
    if (!await requireVerified(context, returnTo: AppRoutes.shell)) return;
    if (!mounted) return;

    if (_nearbyPosition == null) await _useNearbyLocation();
    if (!mounted || _nearbyPosition == null) return;

    final batchId = offer['id']?.toString();
    if (batchId == null) return;

    final titleCtrl = TextEditingController(text: 'Quick piggyback favor');
    final descCtrl = TextEditingController(
      text:
          'Same-street piggyback while the helper is already on my block — quick doorstep favor.',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Street Batch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${offer['helper_name'] ?? 'Helper'} is on '
              '${offer['street_label'] ?? 'your street'}. '
              'Piggyback at ~${offer['discount_pct'] ?? 30}% off.',
              style: AppTextStyles.bodySmall,
            ),
            const Gap(12),
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'What do you need?'),
            ),
            TextField(
              controller: descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Details'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Join at batch price')),
        ],
      ),
    );
    if (ok != true || !mounted) {
      titleCtrl.dispose();
      descCtrl.dispose();
      return;
    }

    try {
      final result = await context.read<TaskRepository>().joinStreetBatch(
            batchId: batchId,
            title: titleCtrl.text.trim().isEmpty
                ? 'Quick piggyback favor'
                : titleCtrl.text.trim(),
            description: descCtrl.text.trim(),
            lat: _nearbyPosition!.latitude,
            lon: _nearbyPosition!.longitude,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Joined batch · ${AppConfig.money(num.tryParse('${result['labor_lkr']}') ?? 0)} '
            '(${result['discount_pct']}% off). ${result['explanation'] ?? ''}',
          ),
          backgroundColor: AppColors.successColor,
        ),
      );
      final auth = context.read<AuthBloc>().state;
      if (auth is AuthAuthenticated) {
        context.read<TaskBloc>().add(TaskFetchClientTasks(auth.profile.id));
      }
      _refreshStreetBatches();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: AppColors.errorColor,
        ),
      );
    } finally {
      titleCtrl.dispose();
      descCtrl.dispose();
    }
  }

  Widget _buildSectionTitle(String title) =>
      SliverToBoxAdapter(child: ZivoSection(title: title));

  Future<void> _openCategory(TaskCategory cat) async {
    final returnTo = '${AppRoutes.createTask}?category=${cat.name}';
    if (!await requireAuth(context, returnTo: returnTo)) return;
    if (!mounted) return;
    if (!await requireVerified(context, returnTo: returnTo)) return;
    if (!mounted) return;
    context.go(AppRoutes.createTask, extra: cat);
  }

  void _showMoreCategories() => _searchServices();

  Future<void> _searchServices() async {
    final category = await showSearch<TaskCategory?>(
      context: context, delegate: ServiceSearch(),
    );
    if (!mounted || category == null) return;
    await _openCategory(category);
  }

  Future<void> _useNearbyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Turn on location services, then try again.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Allow location in your device or browser settings to see nearby helpers.');
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 12),
      );
      if (!mounted) return;
      setState(() => _nearbyPosition = position);
      await Future.wait([_refreshStreetBatches(), _refreshLiveHelpers()]);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Location unavailable. Check device location and browser permissions, then try again. You can still browse services.'),
      ));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Widget _buildLocationControl() => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: OutlinedButton.icon(
        onPressed: _locating ? null : _useNearbyLocation,
        icon: const Icon(Icons.my_location_rounded, size: 18),
        label: Text(_locating ? 'Finding your location…' :
          _nearbyPosition == null ? 'Use my location for nearby help' : 'Nearby your current location · refresh'),
      ),
    ),
  );

  /// Desktop: full category list. Phone: seven services + More.
  Widget _buildCategoryGrid({bool compact = false}) {
    if (!compact) {
      final categories = TaskCategory.values;
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140,
            mainAxisExtent: 148,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _CategoryTile(
              category: categories[i],
              color: _catColor(categories[i]),
              index: i,
              onTap: () => _openCategory(categories[i]),
            ),
            childCount: categories.length,
          ),
        ),
      );
    }

    final primary = CategoryIcon.mobilePrimary;
    final largeText = MediaQuery.textScalerOf(context).scale(12) > 16;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: largeText || MediaQuery.sizeOf(context).width < 350 ? 2 : 4,
          mainAxisExtent: largeText ? 148 : 118,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        delegate: SliverChildBuilderDelegate(
          (ctx, i) {
            if (i == primary.length) {
              return _MoreCategoryTile(
                index: i,
                onTap: _showMoreCategories,
              );
            }
            final cat = primary[i];
            return _CategoryTile(
              category: cat,
              color: _catColor(cat),
              index: i,
              onTap: () => _openCategory(cat),
            );
          },
          childCount: primary.length + 1,
        ),
      ),
    );
  }

  Widget _buildMyTasks() {
    return BlocBuilder<TaskBloc, TaskState>(
      builder: (context, state) {
        if (state is TaskLoading) {
          return SliverToBoxAdapter(
            child: SizedBox(
              height: 140,
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.accent,
                  strokeWidth: 2,
                ),
              ),
            ),
          );
        }

        final bloc = context.read<TaskBloc>();
        final source = state is TaskClientLoaded
            ? state.tasks
            : bloc.peekClientTasks();
        final history = widget.pane == ClientHomePane.tasksOnly;
        final tasks = source.where((task) {
          if (history && _taskFilter == 'All') return true;
          if (history && _taskFilter == 'Completed') return task.status == TaskStatus.completed;
          return !task.status.isTerminal || task.status == TaskStatus.disputed;
        }).toList();
        if (!history && tasks.isEmpty) {
          return const SliverToBoxAdapter(child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Choose a service above. Your progress will appear here.'),
          ));
        }

        if (tasks.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Icon(Icons.receipt_long_outlined, size: 40, color: AppColors.helperAccent),
                const Gap(12),
                Text(_taskFilter == 'Completed' ? 'No completed tasks yet' : 'No tasks here yet', style: AppTextStyles.headingSmall),
                const Gap(8),
                const Text('Your requests and their progress will appear here.'),
                const Gap(16),
                FilledButton(onPressed: _searchServices, child: const Text('Browse services')),
              ]),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _ClientTaskCard(task: tasks[i], index: i),
              childCount: history ? tasks.length : tasks.take(2).length,
            ),
          ),
        );
      },
    );
  }

}

// ── Category Tile ─────────────────────────────────────────────────────────────

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.color,
    required this.index,
    required this.onTap,
  });

  final TaskCategory category;
  final Color color;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.borderColor)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CategoryIconBadge(category, size: 56),
              const Gap(8),
              Text(
                category.displayName,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    ).animate(delay: Duration(milliseconds: 15 * index))
      .fadeIn(duration: 220.ms);
  }
}

class _MoreCategoryTile extends StatelessWidget {
  const _MoreCategoryTile({required this.index, required this.onTap});
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.borderColor)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const MoreIconBadge(size: 56),
              const Gap(8),
              Text(
                'More',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ).animate(delay: Duration(milliseconds: 15 * index))
      .fadeIn(duration: 220.ms);
  }
}

// ── Client Task Card ──────────────────────────────────────────────────────────

Future<void> _openClientDispute(BuildContext context, Task task) async {
  final reasonCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Open dispute'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Escrow stays frozen until ops or Trust review clears this. '
            'Describe what went wrong.',
            style: AppTextStyles.bodySmall,
          ),
          const Gap(12),
          TextField(
            controller: reasonCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'What happened?',
              hintText: 'e.g. Helper arrived late and goods were missing',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Freeze escrow'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) {
    reasonCtrl.dispose();
    return;
  }
  final reason = reasonCtrl.text.trim();
  reasonCtrl.dispose();
  try {
    await context.read<TaskRepository>().openDispute(
          taskId: task.id,
          reason: reason,
        );
    if (!context.mounted) return;
    final auth = context.read<AuthBloc>().state;
    if (auth is AuthAuthenticated) {
      context.read<TaskBloc>().add(TaskFetchClientTasks(auth.profile.id));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dispute opened — escrow frozen'),
        backgroundColor: AppColors.warningColor,
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(humanizeError(e)),
        backgroundColor: AppColors.errorColor,
      ),
    );
  }
}

class _ClientTaskCard extends StatelessWidget {
  const _ClientTaskCard({required this.task, required this.index});
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
    return GestureDetector(
      onTap: () => context.go('/task/${task.id}/track'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderColor),
        ),
        child: Column(
          children: [
            // Category header strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  CategoryIcon(task.category, size: 16),
                  const Gap(8),
                  Expanded(child: Text(
                    task.category.displayName.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.capsLabel.copyWith(
                        color: color, fontSize: 10, letterSpacing: 1.0),
                  ),
                  ),
                  const Gap(8),
                  TaskStatusBadge(status: task.status),
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (task.status == TaskStatus.matched ||
                      task.status == TaskStatus.inProgress) ...[
                    const Gap(10),
                    if (task.helperDisplayName != null)
                      Text(
                        'Helper: ${_ClientHomeScreenState._cleanHelperName(task.helperDisplayName)}',
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.helperAccent,
                        ),
                      ),
                    if (task.startOtp != null || task.endOtp != null) ...[
                      const Gap(8),
                      _ClientOtpBanner(task: task),
                    ],
                  ],
                  if (task.status == TaskStatus.completed) ...[
                    const Gap(12),
                    Text(
                      'Job finished — escrow released.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.successColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const Gap(12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _Chip(icon: Icons.schedule_outlined,
                        label: '${task.estimatedHours}h', color: color),
                      _Chip(icon: Icons.payments_outlined,
                        label: '${AppConfig.money(task.hourlyRate)}/hr',
                        color: color),
                      _Chip(icon: Icons.receipt_long_outlined,
                        label: '${AppConfig.money(task.totalAmount)} total',
                        color: color),
                    ],
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      if (task.status == TaskStatus.matched ||
                          task.status == TaskStatus.inProgress) ...[
                        TextButton.icon(
                          onPressed: () => context.push(
                            AppRoutes.chatFor(task.id, title: task.title),
                          ),
                          icon: const Icon(Icons.chat_bubble_outline_rounded,
                              size: 16),
                          label: const Text('Chat'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.helperAccent,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => showTrustReviewSheet(
                            context,
                            taskId: task.id,
                          ),
                          icon: const Icon(Icons.gavel_rounded, size: 16),
                          label: const Text('Trust'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black87,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _openClientDispute(context, task),
                          icon: const Icon(Icons.report_outlined, size: 16),
                          label: const Text('Dispute'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.warningColor,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: task.status == TaskStatus.open
                              ? AppColors.helperAccent
                              : AppColors.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          task.status == TaskStatus.open
                              ? 'Review Applicants'
                              : task.status == TaskStatus.disputed
                                  ? 'Disputed'
                                  : 'Track',
                          style: AppTextStyles.capsLabel.copyWith(
                            color: Colors.white,
                            letterSpacing: 0.5,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 60 * index))
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.07);
  }
}

class _ClientOtpBanner extends StatefulWidget {
  const _ClientOtpBanner({required this.task});
  final Task task;

  @override
  State<_ClientOtpBanner> createState() => _ClientOtpBannerState();
}

class _ClientOtpBannerState extends State<_ClientOtpBanner> {
  bool _sending = false;
  bool _sent = false;

  Task get task => widget.task;

  Future<void> _sendOtpInChat() async {
    final inProgress = task.status == TaskStatus.inProgress;
    final code = inProgress ? task.endOtp : task.startOtp;
    if (code == null || code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP not ready yet — refresh in a moment')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final body = inProgress
          ? 'End OTP: $code — enter this to finish the job and release escrow.'
          : 'Start OTP: $code — enter this to begin the job.';
      await context.read<TaskRepository>().sendTaskChatMessage(
            taskId: task.id,
            body: body,
          );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            inProgress
                ? 'End OTP sent in chat'
                : 'Start OTP sent in chat',
          ),
          backgroundColor: AppColors.successColor,
          action: SnackBarAction(
            label: 'Open chat',
            textColor: Colors.white,
            onPressed: () => context.push(
              AppRoutes.chatFor(task.id, title: task.title),
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanizeError(e)),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final inProgress = task.status == TaskStatus.inProgress;
    final code = inProgress ? task.endOtp : task.startOtp;
    final title = inProgress
        ? 'End OTP: ${code ?? '----'}'
        : 'Start OTP: ${code ?? '----'}';
    final hint = inProgress
        ? 'When the work looks good, send the End OTP in chat — helper finishes and escrow releases.'
        : 'Helper accepted. Send the Start OTP in chat so they can begin — no need to read it aloud.';
    final accent =
        inProgress ? AppColors.successColor : AppColors.helperAccent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: accent),
              const Gap(8),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Text(
                inProgress ? 'Step 2/2' : 'Step 1/2',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
              A11yReadButton(
                text: '$title. $hint',
              ),
            ],
          ),
          const Gap(6),
          Text(
            hint,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textMuted,
              fontSize: 11,
            ),
          ),
          const Gap(10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _sending || code == null ? null : _sendOtpInChat,
              icon: _sending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _sent ? Icons.check_rounded : Icons.send_rounded,
                      size: 16,
                    ),
              label: Text(
                _sent
                    ? (inProgress ? 'End OTP sent — send again' : 'Start OTP sent — send again')
                    : (inProgress
                        ? 'Send End OTP in chat'
                        : 'Send Start OTP in chat'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const Gap(6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push(
                AppRoutes.chatFor(task.id, title: task.title),
              ),
              child: const Text('Open chat'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const Gap(4),
        Flexible(child: Text(label,
            style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary, fontSize: 11))),
      ],
    );
  }
}

class _EmptyTasksCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: AppColors.accent.withOpacity(0.2),
            style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Text('🙌', style: const TextStyle(fontSize: 36)),
          const Gap(12),
          Text('No active tasks yet',
              style: AppTextStyles.headingSmall,
              textAlign: TextAlign.center),
          const Gap(6),
          Text(
            'Post your first task above and get matched with a real person near you in minutes.',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

