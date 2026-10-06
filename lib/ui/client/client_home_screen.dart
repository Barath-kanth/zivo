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
import 'package:hyperlocal/core/utils/auth_gate.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/models/task_status.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/ui/_shared/zivo_logo.dart';
import 'package:hyperlocal/ui/_shared/task_status_badge.dart';
import 'package:hyperlocal/blocs/mode/mode_cubit.dart';

/// Client Home — Uber-style service marketplace for human tasks.
class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  Timer? _refreshTimer;
  List<Map<String, dynamic>> _streetBatches = const [];
  List<Map<String, dynamic>> _liveHelpers = const [];

  @override
  void initState() {
    super.initState();
    _refreshClientTasks(silent: false);
    _refreshStreetBatches();
    _refreshLiveHelpers();
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

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStreetBatches() async {
    try {
      final res = await context.read<TaskRepository>().listStreetBatches(
            lat: 6.9271,
            lon: 79.8612,
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
    try {
      final res = await context.read<TaskRepository>().listLiveHelpers(
            lat: 6.9271,
            lon: 79.8612,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: CustomScrollView(
        slivers: [
          _buildHeader(),
          _buildSearchBar(),
          _buildInstantDispatchCard(),
          _buildStreetBatchCard(),
          _buildNeighborVouchCard(),
          _buildSectionTitle('What do you need help with?'),
          _buildCategoryGrid(),
          _buildSectionTitle('Your Active Requests'),
          _buildMyTasks(),
          const SliverToBoxAdapter(child: Gap(100)),
        ],
      ),
      floatingActionButton: _buildPostTaskFAB(),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0A0A), Color(0xFF1A1A1A), Color(0xFF111111)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Soft atmosphere — white only (Uber black/white base)
            Positioned(
              top: -40,
              right: -30,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              bottom: 20,
              left: -50,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
                    final currency = AppConfig.currencyCode;

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Brand + account pill
                            Row(
                              children: [
                                const ZivoLogo(
                                  size: 34,
                                  showWordmark: true,
                                  markOnDark: true,
                                  wordmarkColor: Colors.white,
                                ),
                                const Spacer(),
                                Material(
                                  color: Colors.white.withValues(alpha: 0.12),
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
                                          Text(
                                            name,
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const Gap(2),
                                          Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            size: 18,
                                            color: Colors.white
                                                .withValues(alpha: 0.7),
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
                            const Gap(32),
                            // Centered hero
                            Text(
                              'Who can help\nyou today?',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.displayMedium.copyWith(
                                color: Colors.white,
                                fontSize: 34,
                                height: 1.05,
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
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 14,
                              ),
                            )
                                .animate()
                                .fadeIn(delay: 160.ms, duration: 400.ms),
                            const Gap(24),
                            // Centered action tiles
                            Row(
                              children: [
                                Expanded(
                                  child: _headerActionTile(
                                    icon: Icons.handshake_outlined,
                                    label: 'Earn',
                                    sublabel: 'Helper',
                                    accent: AppColors.helperAccent,
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
                                    sublabel:
                                        '$currency ${wallet.toStringAsFixed(0)}',
                                    accent: AppColors.helperAccent,
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
                                    accent: AppColors.helperAccent,
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
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
              const Gap(12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const Gap(2),
              Text(
                sublabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: Colors.white.withValues(alpha: 0.5),
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
                Text(
                  'Describe what you need help with…',
                  style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textMuted),
                ),
                const Spacer(),
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
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
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
                          'Instant Dispatch',
                          style: AppTextStyles.headingSmall.copyWith(fontSize: 14),
                        ),
                        Text(
                          'Algorithmic price · AI dispatch ≤500 m · no bargaining',
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
              title: const Text('Instant Dispatch'),
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
                                      : 'Pay LKR $total',
                                  style: AppTextStyles.headingSmall
                                      .copyWith(fontSize: 15),
                                ),
                                if (fairFloor != null) ...[
                                  const Gap(4),
                                  Text(
                                    'Fair floor LKR $fairFloor'
                                    '${boost != null && boost != 0 ? ' + your tip LKR $boost' : ''}'
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Matched $name · LKR ${labor ?? '—'} locked. '
            '${batch != null ? 'Street batch open for neighbors. ' : ''}'
            '${result['explanation'] ?? ''}',
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
    final name = target['full_name']?.toString() ?? 'Helper';
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
            onTap: badged ? null : () => _vouchHelper(target),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3),
                ),
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
                          style:
                              AppTextStyles.headingSmall.copyWith(fontSize: 14),
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
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
    if (_streetBatches.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final offer = _streetBatches.first;
    final helper = offer['helper_name']?.toString() ?? 'Helper';
    final secs = offer['seconds_left'] ?? 0;
    final price = offer['sample_labor_lkr'];
    final discount = offer['discount_pct'] ?? 30;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Material(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _joinStreetBatch(offer),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.successColor.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.successColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.route_rounded,
                        color: AppColors.successColor),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Street Batch open',
                          style: AppTextStyles.headingSmall.copyWith(fontSize: 14),
                        ),
                        Text(
                          '$helper on your block · ~$discount% off'
                          '${price != null ? ' · from LKR $price' : ''} · ${secs}s left',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Join',
                    style: AppTextStyles.capsLabel.copyWith(
                      color: AppColors.successColor,
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
            lat: 6.9271,
            lon: 79.8612,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Joined batch · LKR ${result['labor_lkr']} '
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

  Widget _buildSectionTitle(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Text(title, style: AppTextStyles.headingSmall),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    final categories = TaskCategory.values;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          childAspectRatio: 1.25,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _CategoryTile(
            category: categories[i],
            color: _catColor(categories[i]),
            index: i,
            onTap: () async {
              final cat = categories[i];
              final returnTo =
                  '${AppRoutes.createTask}?category=${cat.name}';
              if (!await requireAuth(context, returnTo: returnTo)) return;
              if (!mounted) return;
              if (!await requireVerified(context, returnTo: returnTo)) return;
              if (!mounted) return;
              context.go(AppRoutes.createTask, extra: cat);
            },
          ),
          childCount: categories.length,
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
        // Active + just-completed so client can see “finished”
        final tasks = source
            .where((t) =>
                !t.status.isTerminal || t.status == TaskStatus.completed)
            .toList();

        if (tasks.isEmpty) {
          return SliverToBoxAdapter(
            child: _EmptyTasksCard(),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _ClientTaskCard(task: tasks[i], index: i),
              childCount: tasks.length,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPostTaskFAB() {
    return FloatingActionButton.extended(
      onPressed: () async {
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
      backgroundColor: AppColors.accent,
      icon: const Icon(Icons.add_rounded, color: Colors.white),
      label: Text(
        'Post a Task',
        style: AppTextStyles.buttonLabel.copyWith(color: Colors.white),
      ),
      elevation: 6,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              category.emoji,
              style: const TextStyle(fontSize: 28),
            ),
            const Gap(6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                category.displayName,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ),
          ],
        ),
      )
          .animate(delay: Duration(milliseconds: 30 * index))
          .fadeIn(duration: 300.ms)
          .scale(begin: const Offset(0.85, 0.85)),
    );
  }
}

// ── Client Task Card ──────────────────────────────────────────────────────────

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
                  Text(task.category.emoji,
                      style: const TextStyle(fontSize: 16)),
                  const Gap(8),
                  Text(
                    task.category.displayName.toUpperCase(),
                    style: AppTextStyles.capsLabel.copyWith(
                        color: color, fontSize: 10, letterSpacing: 1.0),
                  ),
                  const Spacer(),
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
                  if ((task.status == TaskStatus.matched ||
                          task.status == TaskStatus.inProgress) &&
                      (task.startOtp != null || task.endOtp != null)) ...[
                    const Gap(12),
                    _ClientOtpBanner(task: task),
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
                  Row(
                    children: [
                      _Chip(
                        icon: Icons.schedule_outlined,
                        label: '${task.estimatedHours}h',
                        color: color,
                      ),
                      const Gap(8),
                      _Chip(
                        icon: Icons.payments_outlined,
                        label:
                            'LKR ${task.hourlyRate.toStringAsFixed(2)}/hr  •  LKR ${task.totalAmount.toStringAsFixed(2)} total',
                        color: color,
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: task.status == TaskStatus.open
                              ? AppColors.helperAccent
                              : AppColors.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          task.status == TaskStatus.open
                              ? 'Review Applicants'
                              : 'Track',
                          style: AppTextStyles.capsLabel.copyWith(
                              color: Colors.white,
                              letterSpacing: 0.5,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
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

class _ClientOtpBanner extends StatelessWidget {
  const _ClientOtpBanner({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final inProgress = task.status == TaskStatus.inProgress;
    final code = inProgress ? task.endOtp : task.startOtp;
    final title = inProgress
        ? 'End OTP for helper: ${code ?? '----'}'
        : 'Start OTP for helper: ${code ?? '----'}';
    final hint = inProgress
        ? 'Job is underway. When you are happy with the work, read this End code to the helper — that finishes the job and releases escrow.'
        : 'Give this Start code to the helper to begin. A different End OTP appears here after they start.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (inProgress ? AppColors.successColor : AppColors.accent)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (inProgress ? AppColors.successColor : AppColors.accent)
              .withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: inProgress ? AppColors.successColor : AppColors.accent,
              ),
              const Gap(8),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.bodySmall.copyWith(
                    color:
                        inProgress ? AppColors.successColor : AppColors.accent,
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
        Text(label,
            style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary, fontSize: 11)),
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
