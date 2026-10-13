import 'package:hyperlocal/ui/_shared/category_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/otp/otp_bloc.dart';
import 'package:flutter/services.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Family live link copied. Share it so relatives can see when a helper is coming.\n$link',
          ),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => context.push(path),
          ),
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

        return Scaffold(
          backgroundColor: AppColors.backgroundDark,
          appBar: AppBar(
            title: const Text('Task Tracking'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: _goBack,
            ),
            actions: [
              TextButton.icon(
                onPressed: () => _shareFamilyLive(current),
                icon: const Icon(Icons.share_outlined, size: 18),
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
                    color: AppColors.textMuted,
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
    return MatchExplainCard(
      explanation: explanation,
      reasons: reasons,
      helperName: task.helperDisplayName ??
          selectedCand?['name']?.toString() ??
          'your helper',
      mode: task.matchMode ?? ranking?['mode']?.toString(),
      nearestDeprioritized: ranking?['nearest_deprioritized'] == true,
      compact: true,
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
                  : const Icon(Icons.refresh_rounded, size: 20),
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
              color: AppColors.textMuted,
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

/// Courier-style live tracking: map plane + bottom sheet.
class _LiveTrackingScaffold extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFE8F0EA),
      body: Stack(
        children: [
          // Map plane
          Positioned.fill(
            child: _SimpleTrackMap(
              destinationLabel: _address,
              inProgress: task.status == TaskStatus.inProgress,
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
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 18),
                      onPressed: onBack,
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.94),
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
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Gap(8),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
          // Bottom sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 520),
              margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomPad),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Gap(14),
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 20, color: AppColors.helperAccent),
                      const Gap(8),
                      Expanded(
                        child: Text(
                          _etaLabel,
                          style: AppTextStyles.headingSmall.copyWith(
                            fontSize: 16,
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
                      const Icon(Icons.location_on_rounded,
                          size: 18, color: AppColors.textMuted),
                      const Gap(6),
                      Expanded(
                        child: Text(
                          _address,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
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
                  const Divider(height: 1),
                  const Gap(14),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.brandGreenSoft,
                        child: Text(
                          _helperName.isNotEmpty
                              ? _helperName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
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
                              style: AppTextStyles.headingSmall
                                  .copyWith(fontSize: 14),
                            ),
                            Text(
                              'Helper',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _RoundAction(
                        icon: Icons.chat_bubble_rounded,
                        color: AppColors.helperAccent,
                        onTap: onChat,
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
                        color: Colors.black87,
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
                      title: Text(
                        'Why this match',
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      children: [explainCard],
                    ),
                  ),
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
                      color: AppColors.borderColor,
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                phase,
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                code,
                style: AppTextStyles.headingSmall.copyWith(
                  letterSpacing: 3,
                  fontSize: 20,
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
                backgroundColor: AppColors.helperAccent,
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

/// Lightweight map illustration — no Maps API key required.
class _SimpleTrackMap extends StatelessWidget {
  const _SimpleTrackMap({
    required this.destinationLabel,
    required this.inProgress,
  });

  final String destinationLabel;
  final bool inProgress;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrackMapPainter(inProgress: inProgress),
      child: Stack(
        children: [
          // Soft grid / park blocks
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFDCE8DF),
                    const Color(0xFFEAF2EC),
                    const Color(0xFFD5E4DA),
                  ],
                ),
              ),
            ),
          ),
          CustomPaint(
            size: Size.infinite,
            painter: _TrackMapPainter(inProgress: inProgress),
          ),
          // Destination pin
          const Align(
            alignment: Alignment(0.35, -0.15),
            child: _MapPin(
              icon: Icons.home_rounded,
              color: AppColors.helperAccent,
            ),
          ),
          // Helper pin
          Align(
            alignment: inProgress
                ? const Alignment(0.05, 0.05)
                : const Alignment(-0.45, 0.35),
            child: const _MapPin(
              icon: Icons.directions_walk_rounded,
              color: Color(0xFF1B8A4A),
            ),
          ),
          Positioned(
            right: 16,
            bottom: MediaQuery.sizeOf(context).height * 0.42,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: IconButton(
                tooltip: 'Center',
                onPressed: () {},
                icon: const Icon(Icons.my_location_rounded, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}

class _TrackMapPainter extends CustomPainter {
  _TrackMapPainter({required this.inProgress});
  final bool inProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final route = Paint()
      ..color = const Color(0xFF1B8A4A)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Fake street grid
    for (var i = 1; i < 6; i++) {
      final y = size.height * (i / 7);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), road);
      final x = size.width * (i / 6);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), road);
    }

    final start = Offset(size.width * 0.22, size.height * 0.62);
    final mid = Offset(size.width * 0.48, size.height * 0.48);
    final end = Offset(size.width * 0.68, size.height * 0.38);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(mid.dx, mid.dy + 40, mid.dx, mid.dy)
      ..quadraticBezierTo(end.dx - 20, end.dy + 30, end.dx, end.dy);
    canvas.drawPath(path, route);
  }

  @override
  bool shouldRepaint(covariant _TrackMapPainter oldDelegate) =>
      oldDelegate.inProgress != inProgress;
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
        border: Border.all(color: AppColors.borderColor),
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
              color: AppColors.textMuted,
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
