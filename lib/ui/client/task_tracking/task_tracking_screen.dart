import 'package:hyperlocal/ui/_shared/category_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/otp/otp_bloc.dart';
import 'package:flutter/services.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/models/task_status.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/ui/_shared/task_status_badge.dart';
import 'package:hyperlocal/ui/_shared/empty_state_widget.dart';
import 'package:hyperlocal/ui/_shared/trust_review_sheet.dart';
import 'package:hyperlocal/ui/_shared/match_explain_card.dart';
import 'package:hyperlocal/ui/_shared/a11y_widgets.dart';
import 'package:hyperlocal/ui/accessibility/ability_job_widgets.dart';
import 'package:hyperlocal/ui/accessibility/access_audit_sheet.dart';
import 'package:hyperlocal/ui/_shared/chat_unread_badge.dart';
import 'package:hyperlocal/ui/_shared/zivo_live_map.dart';

class TaskTrackingScreen extends StatefulWidget {
  const TaskTrackingScreen({super.key, required this.taskId});
  final String taskId;

  @override
  State<TaskTrackingScreen> createState() => _TaskTrackingScreenState();
}

class _TaskTrackingScreenState extends State<TaskTrackingScreen> {
  late OtpBloc _otpBloc;
  Map<String, dynamic>? _matchRanking;
  String? _matchError;
  bool _matchLoading = false;
  String? _hiringHelperId;

  @override
  void initState() {
    super.initState();
    _otpBloc = context.read<OtpBloc>();
    _otpBloc.add(OtpSubscribeToTask(widget.taskId));
    _loadMatchRanking();
  }

  Future<void> _loadMatchRanking() async {
    setState(() {
      _matchLoading = true;
      _matchError = null;
    });
    try {
      final ranking =
          await context.read<TaskRepository>().matchHelpers(widget.taskId);
      if (!mounted) return;
      setState(() {
        _matchRanking = ranking;
        _matchLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _matchError = humanizeError(e);
        _matchLoading = false;
      });
    }
  }

  Future<void> _hireHelper(String helperId, String name) async {
    setState(() => _hiringHelperId = helperId);
    try {
      final task = await context.read<TaskRepository>().assignHelper(
            taskId: widget.taskId,
            helperId: helperId,
          );
      if (!mounted) return;
      context.read<OtpBloc>().add(OtpTaskRealtimeUpdated(task));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hired $name — tracking is live.'),
          backgroundColor: AppColors.successColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanizeError(e)),
          backgroundColor: AppColors.errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _hiringHelperId = null);
    }
  }

  @override
  void dispose() {
    _otpBloc.add(OtpUnsubscribeFromTask());
    super.dispose();
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _shareFamilyLive(Task task) async {
    try {
      final res =
          await context.read<TaskRepository>().shareTaskLive(task.id);
      final token = res['share_token']?.toString();
      if (token == null || token.isEmpty) {
        throw StateError('No share token returned');
      }
      final path = AppRoutes.sharedLiveFor(token);
      final origin = Uri.base.origin;
      final link = origin.isNotEmpty && origin != 'null'
          ? '$origin$path'
          : path;
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) return;
      // No sticky snackbar — copy is enough; both client & helper stay clean.
      ScaffoldMessenger.of(context).clearSnackBars();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanizeError(e)),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  Future<void> _openDispute(Task task) async {
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
              'Escrow stays frozen until this is cleared. '
              'Describe what went wrong.',
              style: AppTextStyles.bodySmall,
            ),
            const Gap(12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'What happened?',
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
    if (ok != true || !mounted) {
      reasonCtrl.dispose();
      return;
    }
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    try {
      final updated = await context.read<TaskRepository>().openDispute(
            taskId: task.id,
            reason: reason,
          );
      if (!mounted) return;
      context.read<OtpBloc>().add(OtpTaskRealtimeUpdated(updated));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dispute opened — escrow frozen'),
          backgroundColor: AppColors.warningColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
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
    return BlocBuilder<OtpBloc, OtpState>(
      builder: (context, state) {
        if (state is OtpInitial || state is OtpVerifying) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          );
        }

        Task? task;
        if (state is OtpStateOpen) task = state.task;
        if (state is OtpStateMatched) task = state.task;
        if (state is OtpStateInProgress) task = state.task;
        if (state is OtpStateCompleted) task = state.task;
        if (state is OtpFailure) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Live Tracking'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: _goBack,
              ),
            ),
            body: EmptyStateWidget(
              icon: Icons.error_outline,
              title: 'Error',
              subtitle: state.message,
              color: AppColors.errorColor,
            ),
          );
        }

        if (task == null) return const SizedBox.shrink();
        final current = task;

        final live = current.status == TaskStatus.matched ||
            current.status == TaskStatus.inProgress;

        if (live) {
          return _LiveTrackingScaffold(
            task: current,
            otpState: state,
            onBack: _goBack,
            onChat: () => context.push(
              AppRoutes.chatFor(widget.taskId, title: current.title),
            ),
            onTrust: () => showTrustReviewSheet(
              context,
              taskId: widget.taskId,
            ),
            onDispute: () => _openDispute(current),
            onShareFamily: () => _shareFamilyLive(current),
            explainCard: _buildMatchedExplain(current),
          );
        }

        final palette = ZivoPalette.of(context);
        return Scaffold(
          backgroundColor: palette.canvas,
          appBar: AppBar(
            backgroundColor: palette.canvas,
            foregroundColor: palette.textPrimary,
            title: Text(
              'Task Tracking',
              style: AppTextStyles.headingSmall.copyWith(color: palette.textPrimary),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: palette.textPrimary),
              onPressed: _goBack,
            ),
            actions: [
              TextButton.icon(
                onPressed: () => _shareFamilyLive(current),
                icon: Icon(Icons.share_outlined, size: 18),
                label: const Text('Family live'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              _OpenTaskCard(task: current),
              if (current.bookedForName != null) ...[
                const Gap(8),
                Text(
                  'Booked for ${current.bookedForName}',
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.helperAccent,
                  ),
                ),
              ],
              if (current.bundleTitle != null) ...[
                const Gap(4),
                Text(
                  'Bundle · ${current.bundleTitle}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ZivoPalette.of(context).textMuted,
                  ),
                ),
              ],
              const Gap(16),
              _buildOtpSection(state, current),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMatchedExplain(Task task) {
    final ranking = _matchRanking;
    final selectedId = ranking?['selected_helper_id']?.toString();
    Map? selectedCand;
    final candidates = ranking?['candidates'] as List? ?? const [];
    for (final c in candidates) {
      if (c is Map &&
          (c['helperId']?.toString() == task.helperId ||
              c['helperId']?.toString() == selectedId)) {
        selectedCand = c;
        break;
      }
    }
    final reasons = task.matchReasons.isNotEmpty
        ? task.matchReasons
        : (selectedCand?['reasons'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
    final explanation = (task.matchExplanation != null &&
            task.matchExplanation!.trim().isNotEmpty)
        ? task.matchExplanation!
        : ranking?['explanation']?.toString() ??
            'Matched using skills, distance, availability and trust.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccessAuditCard(
          task: task,
          onAdd: () async {
            final res = await showAccessAudit(context, taskId: task.id);
            if (res != null && mounted) setState(() {});
          },
        ),
        AccessNoteCard(
          task: task,
          onChanged: () {
            if (mounted && context.canPop()) context.pop();
          },
        ),
        MatchExplainCard(
          explanation: explanation,
          reasons: reasons,
          helperName: task.helperDisplayName ??
              selectedCand?['name']?.toString() ??
              'your helper',
          mode: task.matchMode ?? ranking?['mode']?.toString(),
          nearestDeprioritized: ranking?['nearest_deprioritized'] == true,
          compact: true,
        ),
      ],
    );
  }

  Widget _buildOtpSection(OtpState state, Task task) {
    if (state is OtpStateOpen) {
      return _buildApplicantsSection(task);
    }
    if (state is OtpStateCompleted) {
      return _CompletedCard(task: task);
    }
    return const SizedBox.shrink();
  }

  Widget _buildApplicantsSection(Task task) {
    final ranking = _matchRanking;
    final candidates = ranking?['candidates'] as List? ?? const [];
    final explanation = ranking?['explanation']?.toString() ?? '';
    final nearestDep = ranking?['nearest_deprioritized'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Choose a helper',
                style: AppTextStyles.headingMedium,
              ),
            ),
            IconButton(
              tooltip: 'Refresh ranking',
              onPressed: _matchLoading ? null : _loadMatchRanking,
              icon: _matchLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        const Gap(8),
        if (_matchLoading && ranking == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_matchError != null && ranking == null)
          Text(_matchError!, style: AppTextStyles.bodySmall)
        else if (candidates.isEmpty)
          Text(
            'No verified helpers in range yet. They can still accept from Jobs.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: ZivoPalette.of(context).textMuted,
            ),
          )
        else ...[
          if (explanation.isNotEmpty)
            MatchExplainCard(
              explanation: explanation,
              mode: ranking?['mode']?.toString(),
              nearestDeprioritized: nearestDep,
              helperName: ranking?['selected_helper_name']?.toString(),
              compact: true,
            ),
          const Gap(14),
          ...candidates.whereType<Map>().take(5).map((c) {
            final id = c['helperId']?.toString() ?? '';
            final name = c['name']?.toString() ?? 'Helper';
            final dist = (c['distanceKm'] as num?)?.toDouble() ?? 0;
            final score = (c['score'] as num?)?.toInt() ?? 0;
            final reasons = (c['reasons'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                const <String>[];
            final recommended =
                id == ranking?['selected_helper_id']?.toString();
            return MatchCandidateTile(
              name: name,
              distanceKm: dist,
              score: score,
              reasons: reasons,
              trustTier: c['trust_tier']?.toString(),
              disputeCount: (c['dispute_count'] as num?)?.toInt(),
              recommended: recommended,
              hiring: _hiringHelperId == id,
              onHire: id.isEmpty ? null : () => _hireHelper(id, name),
            );
          }),
        ],
      ],
    );
  }
}

/// Courier-style live tracking: Google Map plane + collapsible bottom sheet.
class _LiveTrackingScaffold extends StatefulWidget {
  const _LiveTrackingScaffold({
    required this.task,
    required this.otpState,
    required this.onBack,
    required this.onChat,
    required this.onTrust,
    required this.onDispute,
    required this.onShareFamily,
    required this.explainCard,
  });

  final Task task;
  final OtpState otpState;
  final VoidCallback onBack;
  final VoidCallback onChat;
  final VoidCallback onTrust;
  final VoidCallback onDispute;
  final VoidCallback onShareFamily;
  final Widget explainCard;

  @override
  State<_LiveTrackingScaffold> createState() => _LiveTrackingScaffoldState();
}

class _LiveTrackingScaffoldState extends State<_LiveTrackingScaffold> {
  /// When true, the card collapses so the Google Map fills the screen.
  bool _mapFocused = false;

  Task get task => widget.task;
  OtpState get otpState => widget.otpState;
  VoidCallback get onBack => widget.onBack;
  VoidCallback get onChat => widget.onChat;
  VoidCallback get onTrust => widget.onTrust;
  VoidCallback get onDispute => widget.onDispute;
  VoidCallback get onShareFamily => widget.onShareFamily;
  Widget get explainCard => widget.explainCard;

  String get _etaLabel {
    final mins = (task.estimatedHours * 60).round().clamp(5, 180);
    if (task.status == TaskStatus.inProgress) {
      return 'Helper on the job · ~$mins min left';
    }
    return 'Helper en route · arriving in ~$mins min';
  }

  String get _helperName => task.helperDisplayName ?? 'Your helper';

  String get _address =>
      task.locationLabel ??
      task.locationAddress ??
      'Task location nearby';

  void _openFullMap() {
    openZivoLiveMap(
      context,
      center: task.location,
      label: _address,
      showHelpers: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final palette = ZivoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final pin = task.location;

    return Scaffold(
      backgroundColor: isDark ? palette.canvas : const Color(0xFFE8F0EA),
      body: Stack(
        children: [
          // Google Maps — tap empty map (when focused) or expand for fullscreen.
          Positioned.fill(
            child: _mapFocused
                ? GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _openFullMap,
                    child: AbsorbPointer(
                      child: ZivoLiveMapFill(center: pin),
                    ),
                  )
                : AbsorbPointer(
                    child: ZivoLiveMapFill(center: pin),
                  ),
          ),
          // Top bar
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  Material(
                    color: palette.card,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: palette.textPrimary,
                      ),
                      onPressed: onBack,
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: Material(
                      color: palette.card.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(22),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Text(
                          'Live Tracking',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.headingSmall.copyWith(
                            fontSize: 16,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Gap(8),
                  Material(
                    color: palette.card,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      tooltip: 'Expand map',
                      icon: Icon(
                        Icons.open_in_full_rounded,
                        size: 18,
                        color: palette.accent,
                      ),
                      onPressed: _openFullMap,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom sheet — collapses when "See whole map" so map fills the view.
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 520),
              margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomPad),
              padding: EdgeInsets.fromLTRB(
                18,
                10,
                18,
                _mapFocused ? 12 : 16,
              ),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: palette.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (d) {
                      if (d.primaryDelta != null && d.primaryDelta! > 10) {
                        setState(() => _mapFocused = true);
                      } else if (d.primaryDelta != null &&
                          d.primaryDelta! < -10) {
                        setState(() => _mapFocused = false);
                      }
                    },
                    onTap: () {
                      if (_mapFocused) setState(() => _mapFocused = false);
                    },
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  if (_mapFocused) ...[
                    const Gap(10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _etaLabel,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _mapFocused = false),
                          child: Text(
                            'Show details',
                            style: TextStyle(
                              color: palette.accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                  const Gap(8),
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() => _mapFocused = true);
                      },
                      icon: Icon(Icons.map_rounded,
                          size: 16, color: palette.accent),
                      label: Text(
                        'See whole map',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const Gap(6),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded,
                          size: 20, color: AppColors.helperAccent),
                      const Gap(8),
                      Expanded(
                        child: Text(
                          _etaLabel,
                          style: AppTextStyles.headingSmall.copyWith(
                            fontSize: 16,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      TaskStatusBadge(status: task.status),
                    ],
                  ),
                  const Gap(10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.location_on_rounded,
                          size: 18, color: palette.textMuted),
                      const Gap(6),
                      Expanded(
                        child: Text(
                          _address,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(6),
                  Row(
                    children: [
                      CategoryIcon(task.category, size: 18),
                      const Gap(8),
                      Expanded(
                        child: Text(
                          task.title,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        AppConfig.money(task.totalAmount),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.helperAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const Gap(14),
                  Divider(height: 1, color: palette.border),
                  const Gap(14),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: isDark
                            ? palette.accent.withValues(alpha: 0.22)
                            : AppColors.brandGreenSoft,
                        child: Text(
                          _helperName.isNotEmpty
                              ? _helperName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _helperName,
                              style: AppTextStyles.headingSmall.copyWith(
                                fontSize: 14,
                                color: palette.textPrimary,
                              ),
                            ),
                            Text(
                              'Helper',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: palette.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ChatUnreadPoller(
                        taskId: task.id,
                        builder: (context, unread) => ChatUnreadBadge(
                          count: unread,
                          child: _RoundAction(
                            icon: Icons.chat_bubble_rounded,
                            color: AppColors.helperAccent,
                            onTap: onChat,
                          ),
                        ),
                      ),
                      const Gap(8),
                      _RoundAction(
                        icon: Icons.family_restroom_outlined,
                        color: AppColors.helperAccent,
                        onTap: onShareFamily,
                      ),
                      const Gap(8),
                      _RoundAction(
                        icon: Icons.gavel_rounded,
                        // Uber blue in dark so Trust never blends into black.
                        color: isDark ? palette.accent : Colors.black87,
                        onTap: onTrust,
                      ),
                      const Gap(8),
                      _RoundAction(
                        icon: Icons.report_outlined,
                        color: AppColors.warningColor,
                        onTap: onDispute,
                      ),
                    ],
                  ),
                  if (task.needsCompletionProof) ...[
                    const Gap(12),
                    _ClientProofStrip(task: task),
                  ],
                  const Gap(14),
                  _LiveOtpStrip(state: otpState, task: task),
                  const Gap(10),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      iconColor: palette.textMuted,
                      collapsedIconColor: palette.textMuted,
                      title: Text(
                        'Why this match',
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                      children: [explainCard],
                    ),
                  ),
                  ],
                ],
              ),
            ).animate().slideY(begin: 0.12, duration: 320.ms, curve: Curves.easeOutCubic),
          ),
        ],
      ),
    );
  }
}

class _ClientProofStrip extends StatelessWidget {
  const _ClientProofStrip({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final done = task.hasCompletionProof;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (done ? AppColors.successColor : AppColors.warningColor)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (done ? AppColors.successColor : AppColors.warningColor)
              .withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.verified_outlined : Icons.pending_actions_outlined,
                size: 18,
                color: done ? AppColors.successColor : AppColors.warningColor,
              ),
              const Gap(8),
              Expanded(
                child: Text(
                  done
                      ? 'Proof submitted — review then share End OTP'
                      : 'Waiting for helper completion proof',
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ZivoPalette.of(context).textPrimary,
                  ),
                ),
              ),
              A11yReadButton(
                text: done
                    ? 'Proof submitted. ${task.proofCheckedItems.join('. ')}'
                    : 'Waiting for helper completion proof',
              ),
            ],
          ),
          if (done && task.proofCheckedItems.isNotEmpty) ...[
            const Gap(8),
            ...task.proofCheckedItems.take(4).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '✓ $item',
                      style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
                    ),
                  ),
                ),
          ],
          if (done && task.proofPhotoUrls.isNotEmpty) ...[
            const Gap(8),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: task.proofPhotoUrls.length.clamp(0, 3),
                separatorBuilder: (_, __) => const Gap(8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    task.proofPhotoUrls[i],
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 56,
                      height: 56,
                      color: ZivoPalette.of(context).border,
                      child: const Icon(Icons.image_outlined, size: 18),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _LiveOtpStrip extends StatefulWidget {
  const _LiveOtpStrip({required this.state, required this.task});
  final OtpState state;
  final Task task;

  @override
  State<_LiveOtpStrip> createState() => _LiveOtpStripState();
}

class _LiveOtpStripState extends State<_LiveOtpStrip> {
  bool _sending = false;

  Future<void> _sendOtp() async {
    final inProgress = widget.state is OtpStateInProgress;
    final code = inProgress ? widget.task.endOtp : widget.task.startOtp;
    if (code == null || code.isEmpty) return;
    setState(() => _sending = true);
    try {
      await context.read<TaskRepository>().sendTaskChatMessage(
            taskId: widget.task.id,
            body: inProgress
                ? 'End OTP: $code — enter this to finish the job and release escrow.'
                : 'Start OTP: $code — enter this to begin the job.',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(inProgress ? 'End OTP sent in chat' : 'Start OTP sent in chat'),
          backgroundColor: AppColors.successColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanizeError(e)),
          backgroundColor: AppColors.errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String phase;
    String code;
    if (widget.state is OtpStateMatched) {
      phase = 'Start OTP';
      code = widget.task.startOtp ?? '------';
    } else if (widget.state is OtpStateInProgress) {
      phase = 'End OTP';
      code = widget.task.endOtp ?? '------';
    } else {
      return const SizedBox.shrink();
    }

    final palette = ZivoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111111) : palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                phase,
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: palette.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                code,
                style: AppTextStyles.headingSmall.copyWith(
                  letterSpacing: 3,
                  fontSize: 20,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
          const Gap(10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _sendOtp,
              icon: _sending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(
                widget.state is OtpStateInProgress
                    ? 'Send End OTP in chat'
                    : 'Send Start OTP in chat',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isDark ? palette.accent : AppColors.helperAccent,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenTaskCard extends StatelessWidget {
  const _OpenTaskCard({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ZivoPalette.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryIcon(task.category, size: 22),
              const Gap(10),
              Expanded(
                child: Text(task.title, style: AppTextStyles.headingSmall),
              ),
              TaskStatusBadge(status: task.status),
            ],
          ),
          const Gap(10),
          Text(
            task.locationLabel ?? task.locationAddress ?? 'Nearby',
            style: AppTextStyles.bodySmall.copyWith(
              color: ZivoPalette.of(context).textMuted,
            ),
          ),
          const Gap(6),
          Text(
            '${AppConfig.money(task.totalAmount)} · ${task.estimatedHours}h',
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedCard extends StatelessWidget {
  const _CompletedCard({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final disputed = task.status == TaskStatus.disputed;
    final accent =
        disputed ? AppColors.warningColor : AppColors.successColor;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(
            disputed
                ? Icons.report_outlined
                : Icons.check_circle_rounded,
            color: accent,
            size: 56,
          ),
          const Gap(12),
          Text(
            disputed ? 'Escrow frozen' : 'Task complete',
            style: AppTextStyles.headingMedium,
          ),
          const Gap(6),
          Text(
            disputed
                ? (task.disputeReason?.isNotEmpty == true
                    ? 'Dispute: ${task.disputeReason}'
                    : 'This job is disputed — escrow will not release until cleared.')
                : 'Escrow released for "${task.title}".',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium,
          ),
          const Gap(16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/'),
              style: ElevatedButton.styleFrom(backgroundColor: accent),
              child: const Text('Back to Home'),
            ),
          ),
        ],
      ),
    ).animate().scale(duration: 500.ms, curve: Curves.elasticOut);
  }
}
