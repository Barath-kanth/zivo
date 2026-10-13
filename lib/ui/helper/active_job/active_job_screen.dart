import 'package:hyperlocal/ui/_shared/category_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/models/task_status.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/ui/_shared/task_status_badge.dart';
import 'package:hyperlocal/ui/_shared/empty_state_widget.dart';
import 'package:hyperlocal/ui/_shared/task_photo_gallery.dart';
import 'package:hyperlocal/blocs/otp/otp_bloc.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/task/task_bloc.dart';
import 'package:hyperlocal/blocs/wallet/wallet_bloc.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/ui/_shared/trust_review_sheet.dart';

class ActiveJobScreen extends StatefulWidget {
  const ActiveJobScreen({super.key, required this.taskId});
  final String taskId;

  @override
  State<ActiveJobScreen> createState() => _ActiveJobScreenState();
}

class _ActiveJobScreenState extends State<ActiveJobScreen> {
  /// Matches GCP task start/end OTP (4 digits — see store.ts).
  static const int _otpLength = 4;

  final List<TextEditingController> _otpControllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_otpLength, (_) => FocusNode());

  late OtpBloc _otpBloc;

  String get _enteredOtp =>
      _otpControllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    _otpBloc = context.read<OtpBloc>();
    _otpBloc.add(OtpSubscribeToTask(widget.taskId));
  }

  @override
  void dispose() {
    for (final c in _otpControllers) c.dispose();
    for (final n in _focusNodes) n.dispose();
    _otpBloc.add(OtpUnsubscribeFromTask());
    super.dispose();
  }

  void _clearOtp() {
    for (final c in _otpControllers) c.clear();
    _focusNodes.first.requestFocus();
  }

  void _submitOtp(OtpState state) {
    if (_enteredOtp.length != _otpLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enter all $_otpLength digits')),
      );
      return;
    }

    if (state is OtpStateMatched) {
      context.read<OtpBloc>().add(OtpVerifyStart(
        taskId: widget.taskId,
        enteredOtp: _enteredOtp,
      ));
    } else if (state is OtpStateInProgress) {
      context.read<OtpBloc>().add(OtpVerifyEnd(
        taskId: widget.taskId,
        enteredOtp: _enteredOtp,
      ));
    }
    _clearOtp();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        title: const Text('Active Job'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.go('/'),
        ),
        actions: [
          IconButton(
            tooltip: 'Chat with client',
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            onPressed: () {
              context.push(AppRoutes.chatFor(widget.taskId));
            },
          ),
        ],
      ),
      body: BlocConsumer<OtpBloc, OtpState>(
        listener: (context, state) {
          if (state is OtpStateCompleted) {
            final auth = context.read<AuthBloc>().state;
            final helperId = auth is AuthAuthenticated
                ? auth.profile.id
                : (state.task.helperId ?? '');
            if (helperId.isEmpty) return;
            context.read<WalletBloc>().add(WalletCreditHelperEarnings(
                  userId: helperId,
                  taskId: state.task.id,
                  amount: state.task.totalAmount,
                  taskTitle: state.task.title,
                ));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '🎉 Job complete! +LKR ${state.task.totalAmount.toStringAsFixed(2)} added to helper wallet.',
                ),
                backgroundColor: AppColors.successColor,
              ),
            );
          }
          if (state is OtpFailure && state.message != 'Task not found') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppColors.errorColor,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is OtpInitial) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.helperAccent),
            );
          }

          if (state is OtpStateCompleted) {
            return _CompletedView(task: state.task);
          }

          Task? task;
          String? errorMessage;

          if (state is OtpStateMatched) {
            task = state.task;
            errorMessage = state.errorMessage;
          } else if (state is OtpStateInProgress) {
            task = state.task;
            errorMessage = state.errorMessage;
          }

          if (task == null || state is OtpFailure) {
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Center(
                child: EmptyStateWidget(
                  icon: Icons.work_outline_rounded,
                  title: 'No Active Job',
                  subtitle: 'Browse the Job Feed to accept a task and start earning!',
                  color: AppColors.helperAccent,
                ),
              ),
            );
          }

          final isVerifying = state is OtpVerifying;
          final isInProgress = state is OtpStateInProgress;
          final activeTask = task;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusBar(activeTask, isInProgress),
                const Gap(20),
                _buildTaskDetail(activeTask),
                const Gap(12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(
                      AppRoutes.chatFor(
                        widget.taskId,
                        title: activeTask.title,
                      ),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Chat with client'),
                  ),
                ),
                const Gap(8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => showTrustReviewSheet(
                      context,
                      taskId: widget.taskId,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.helperAccent,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.gavel_rounded, size: 18),
                    label: const Text('Trust Arbitrator'),
                  ),
                ),
                if (isInProgress &&
                    activeTask.requiresPurchaseProof &&
                    activeTask.proofSubmittedAt == null) ...[
                  const Gap(16),
                  _buildProofGate(activeTask),
                ],
                if (isInProgress && activeTask.proofSubmittedAt != null) ...[
                  const Gap(12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.helperAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Receipt submitted (${AppConfig.money(activeTask.goodsSpent)}). '
                      'Wait for client to check goods, then enter End OTP.',
                      style: AppTextStyles.bodySmall,
                    ),
                  ),
                ],
                const Gap(24),
                _buildOtpInput(
                  state: state,
                  task: activeTask,
                  isVerifying: isVerifying,
                  isInProgress: isInProgress,
                  errorMessage: errorMessage,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProofGate(Task task) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warningColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Purchase proof required',
              style: AppTextStyles.headingSmall),
          const Gap(6),
          Text(
            'Pillar B: photograph the till receipt + confirm the shopping list. '
            'Receipt check reconciles items / anomalies / total vs budget '
            '(${AppConfig.money(task.goodsBudget)}). Never take cash from the client.',
            style: AppTextStyles.bodySmall,
          ),
          const Gap(12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _showProofDialog(task),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              child: const Text('Run receipt reconciliation'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showProofDialog(Task task) async {
    final listCtrl = TextEditingController(
      text: task.description.trim().isNotEmpty
          ? task.description.trim()
          : 'rice, eggs, milk, bread',
    );
    final storeCtrl = TextEditingController(text: 'Cargills / Keells');
    List<int>? receiptBytes;
    String? receiptName;
    var submitting = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Pillar B · Receipt vs list'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Demo: photograph a messy/crumpled receipt. Keyword OCR often fails; '
                      'Shows matched / missing / anomalies / total vs budget.',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textMuted, fontSize: 11),
                    ),
                    const Gap(10),
                    TextField(
                      controller: storeCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Store name'),
                    ),
                    TextField(
                      controller: listCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Original item list',
                        hintText: 'rice, eggs, milk…',
                      ),
                    ),
                    const Gap(8),
                    Text(
                      'Budget: ${AppConfig.money(task.goodsBudget)}',
                      style: AppTextStyles.bodySmall,
                    ),
                    const Gap(10),
                    OutlinedButton.icon(
                      onPressed: submitting
                          ? null
                          : () async {
                              final picker = ImagePicker();
                              final file = await picker.pickImage(
                                source: ImageSource.camera,
                                maxWidth: 1600,
                                imageQuality: 85,
                              );
                              if (file == null) return;
                              final bytes = await file.readAsBytes();
                              setLocal(() {
                                receiptBytes = bytes;
                                receiptName = file.name;
                              });
                            },
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(
                        receiptBytes == null
                            ? 'Photograph receipt'
                            : 'Receipt ready (${receiptName ?? 'image'})',
                      ),
                    ),
                    if (receiptBytes == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Gallery fallback available after canceling camera.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    TextButton(
                      onPressed: submitting
                          ? null
                          : () async {
                              final picker = ImagePicker();
                              final file = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1600,
                                imageQuality: 85,
                              );
                              if (file == null) return;
                              final bytes = await file.readAsBytes();
                              setLocal(() {
                                receiptBytes = bytes;
                                receiptName = file.name;
                              });
                            },
                      child: const Text('Pick from gallery instead'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      submitting ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          if (listCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Enter the shopping list'),
                              ),
                            );
                            return;
                          }
                          setLocal(() => submitting = true);
                          try {
                            final data = await context
                                .read<TaskRepository>()
                                .submitPurchaseProof(
                                  taskId: task.id,
                                  shoppingList: listCtrl.text.trim(),
                                  receiptImageBytes: receiptBytes,
                                  budgetLkr: task.goodsBudget,
                                  storeName: storeCtrl.text.trim(),
                                );
                            if (ctx.mounted) Navigator.pop(ctx, data);
                          } catch (e) {
                            setLocal(() => submitting = false);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('$e'),
                                backgroundColor: AppColors.errorColor,
                              ),
                            );
                          }
                        },
                  child: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Reconcile'),
                ),
              ],
            );
          },
        );
      },
    );

    listCtrl.dispose();
    storeCtrl.dispose();
    if (result == null || !mounted) return;

    await _showPillarBVerdict(result);
    if (!mounted) return;
    context.read<OtpBloc>().add(OtpSubscribeToTask(task.id));
  }

  Future<void> _showPillarBVerdict(Map<String, dynamic> result) async {
    final verdict = result['verdict']?.toString() ?? 'review';
    final mode = result['mode']?.toString() ?? '—';
    final matched = (result['items_matched'] as List?)?.cast<dynamic>() ??
        (result['itemsFound'] as List?)?.cast<dynamic>() ??
        const [];
    final missing = (result['items_missing'] as List?)?.cast<dynamic>() ??
        (result['missingVsList'] as List?)?.cast<dynamic>() ??
        const [];
    final anomalies =
        (result['price_anomalies'] as List?)?.cast<dynamic>() ?? const [];
    final tvb = result['total_vs_budget'] as Map?;
    final accent = verdict == 'pass'
        ? AppColors.successColor
        : verdict == 'fail'
            ? AppColors.errorColor
            : AppColors.warningColor;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pillar B · ${verdict.toUpperCase()} · $mode'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                result['explanation']?.toString() ?? 'Reconciliation done.',
                style: AppTextStyles.bodySmall,
              ),
              const Gap(10),
              Text(
                  'Matched: ${matched.isEmpty ? '—' : matched.join(', ')}',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.successColor)),
              Text(
                  'Missing: ${missing.isEmpty ? '—' : missing.join(', ')}',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.errorColor)),
              if (anomalies.isNotEmpty)
                Text('Anomalies: ${anomalies.join('; ')}',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.warningColor)),
              if (tvb != null) ...[
                const Gap(8),
                Text(
                  'Total ${tvb['receipt_total_lkr']} vs budget ${tvb['budget_lkr']} '
                  '(Δ ${tvb['delta_lkr']}) · within=${tvb['within_budget']}',
                  style: AppTextStyles.bodySmall.copyWith(color: accent),
                ),
              ],
              if (result['research_note'] != null) ...[
                const Gap(10),
                Text(
                  result['research_note'].toString(),
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continue to End OTP'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(Task task, bool isInProgress) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isInProgress
              ? [AppColors.helperAccent.withOpacity(0.15), Colors.transparent]
              : [AppColors.accent.withOpacity(0.15), Colors.transparent],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isInProgress
              ? AppColors.helperAccent.withOpacity(0.3)
              : AppColors.accent.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isInProgress ? AppColors.helperAccent : AppColors.statusMatched,
              shape: BoxShape.circle,
            ),
          ).animate(onPlay: (c) => c.repeat())
              .scaleXY(end: 1.5, duration: 700.ms, curve: Curves.easeInOut),
          const Gap(10),
          Text(
            isInProgress ? 'Task is underway' : 'Waiting for Start OTP',
            style: AppTextStyles.labelLarge.copyWith(
              color: isInProgress ? AppColors.helperAccent : AppColors.statusMatched,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskDetail(Task task) {
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
              CategoryIcon(task.category, size: 22),
              const Gap(10),
              Expanded(child: Text(task.title, style: AppTextStyles.headingSmall)),
              TaskStatusBadge(status: task.status),
            ],
          ),
          const Gap(10),
          Text(task.description, style: AppTextStyles.bodyMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
          if (task.photoUrls.isNotEmpty) ...[
            const Gap(12),
            TaskPhotoGallery(photoUrls: task.photoUrls, height: 110),
          ],
          const Divider(height: 20),
          Row(
            children: [
              _DetailChip(Icons.schedule_rounded, '${task.estimatedHours}h'),
              const Gap(10),
              _DetailChip(Icons.payments_outlined, 'LKR ${(task.totalAmount * 0.9).toStringAsFixed(2)} earnings'),
              const Gap(10),
              if (task.locationLabel != null)
                _DetailChip(Icons.location_on_outlined, task.locationLabel!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOtpInput({
    required OtpState state,
    required Task task,
    required bool isVerifying,
    required bool isInProgress,
    String? errorMessage,
  }) {
    final accentColor = isInProgress ? AppColors.helperAccent : AppColors.accent;
    final phaseLabel = isInProgress ? 'End OTP' : 'Start OTP';
    final instruction = isInProgress
        ? (task.requiresPurchaseProof && task.proofSubmittedAt == null
            ? 'Upload supermarket receipt + bag photos first. End OTP is blocked until proof is submitted — never take cash from the client.'
            : 'Enter the End OTP shown on the client’s phone after they check goods vs receipt. Earnings + goods reimbursement then release from escrow.')
        : 'Enter the Start OTP shown on the client’s phone to begin.';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  phaseLabel,
                  style: AppTextStyles.capsLabel.copyWith(color: accentColor),
                ),
              ),
            ],
          ),
          const Gap(12),
          Text(instruction, style: AppTextStyles.bodyMedium),
          const Gap(24),

          // OTP digit boxes (4 — same as client Start/End OTP)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_otpLength, (i) => _OtpBox(
              controller: _otpControllers[i],
              focusNode: _focusNodes[i],
              nextFocus: i < _otpLength - 1 ? _focusNodes[i + 1] : null,
              prevFocus: i > 0 ? _focusNodes[i - 1] : null,
              accentColor: accentColor,
            )),
          ),

          if (errorMessage != null) ...[
            const Gap(12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.errorColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_rounded, color: AppColors.errorColor, size: 16),
                  const Gap(8),
                  Expanded(
                    child: Text(
                      errorMessage,
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.errorColor),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Gap(24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isVerifying ? null : () => _submitOtp(state),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: isVerifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(
                      isInProgress ? 'Verify End OTP & Complete' : 'Verify Start OTP',
                      style: AppTextStyles.buttonLabel.copyWith(color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05);
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.accentColor,
    this.nextFocus,
    this.prevFocus,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode? nextFocus;
  final FocusNode? prevFocus;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 54,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.number,
        maxLength: 1,
        textAlign: TextAlign.center,
        style: AppTextStyles.headingMedium.copyWith(color: accentColor),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: AppColors.otpBoxBg,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.borderColor, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: accentColor, width: 2),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (value) {
          if (value.isNotEmpty && nextFocus != null) {
            nextFocus!.requestFocus();
          } else if (value.isEmpty && prevFocus != null) {
            prevFocus!.requestFocus();
          }
        },
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textMuted),
        const Gap(4),
        Text(label, style: AppTextStyles.bodySmall),
      ],
    );
  }
}

class _CompletedView extends StatelessWidget {
  const _CompletedView({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final earnings = task.totalAmount * 0.9;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.celebration_rounded,
              color: AppColors.helperAccent,
              size: 72,
            ).animate()
                .scale(duration: 600.ms, curve: Curves.elasticOut)
                .fadeIn(duration: 300.ms),
            const Gap(24),
            Text('Job Complete!', style: AppTextStyles.headingLarge)
                .animate().fadeIn(delay: 200.ms),
            const Gap(8),
            Text(
              'Great work! Your earnings have been credited to your helper wallet.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 300.ms),
            const Gap(32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.helperAccent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.helperAccent.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text('You Earned', style: AppTextStyles.bodyMedium),
                  const Gap(4),
                  Text(
                    'LKR ${earnings.toStringAsFixed(2)}',
                    style: AppTextStyles.moneyLarge.copyWith(color: AppColors.helperAccent),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 400.ms).scale(begin: const Offset(0.8, 0.8)),
            const Gap(32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // Ensure completed job is cleared from active lists
                  context.read<TaskBloc>().syncDemoTaskStatus(
                        task.copyWith(
                          status: TaskStatus.completed,
                          completedAt: task.completedAt ?? DateTime.now(),
                        ),
                      );
                  context.go('/');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.helperAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Back to Job Feed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ).animate().fadeIn(delay: 500.ms),
          ],
        ),
      ),
    );
  }
}
