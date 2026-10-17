import 'package:hyperlocal/ui/_shared/category_icon.dart';
import 'package:flutter/material.dart';
import 'package:hyperlocal/ui/accessibility/ability_job_widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/models/task_status.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/ui/_shared/task_status_badge.dart';
import 'package:hyperlocal/ui/_shared/empty_state_widget.dart';
import 'package:hyperlocal/ui/_shared/task_photo_gallery.dart';
import 'package:hyperlocal/blocs/otp/otp_bloc.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/mode/mode_cubit.dart';
import 'package:hyperlocal/blocs/task/task_bloc.dart';
import 'package:hyperlocal/blocs/wallet/wallet_bloc.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/ui/_shared/trust_review_sheet.dart';
import 'package:hyperlocal/ui/_shared/chat_unread_badge.dart';

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

  /// Always return to helper Jobs — never dump onto client home.
  Future<void> _goBackToHelperHome() async {
    try {
      await context.read<ModeCubit>().ensureHelperWorkspace();
    } catch (_) {
      /* KYC block — still leave Active Job */
    }
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.shell);
    }
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _goBackToHelperHome();
      },
      child: Builder(
        builder: (context) {
          final palette = ZivoPalette.of(context);
          return Scaffold(
        backgroundColor: palette.canvas,
        appBar: AppBar(
          backgroundColor: palette.canvas,
          foregroundColor: palette.textPrimary,
          elevation: 0,
          title: Text(
            'Your active job',
            style: AppTextStyles.headingSmall.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
            ),
          ),
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: palette.textPrimary,
            ),
            onPressed: _goBackToHelperHome,
          ),
          actions: [
            ChatUnreadPoller(
              taskId: widget.taskId,
              builder: (context, unread) => IconButton(
                tooltip: 'Chat with client',
                icon: ChatUnreadBadge(
                  count: unread,
                  child: const Icon(Icons.chat_bubble_outline_rounded),
                ),
                onPressed: () {
                  context.push(AppRoutes.chatFor(widget.taskId));
                },
              ),
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
            // Refresh from server — never invent local helper earnings.
            context.read<WalletBloc>().add(WalletFetchRequested(helperId));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Job complete! +${AppConfig.money(state.task.totalAmount)} added to helper wallet.',
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
            return _CompletedView(
              task: state.task,
              onBack: _goBackToHelperHome,
            );
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
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const EmptyStateWidget(
                      icon: Icons.work_outline_rounded,
                      title: 'No Active Job',
                      subtitle:
                          'Browse Jobs to accept a task and start earning!',
                      color: AppColors.helperAccent,
                    ),
                    const Gap(16),
                    FilledButton(
                      onPressed: _goBackToHelperHome,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.helperAccent,
                      ),
                      child: const Text('Back to Jobs'),
                    ),
                  ],
                ),
              ),
            );
          }

          final isVerifying = state is OtpVerifying;
          final isInProgress = state is OtpStateInProgress;
          final activeTask = task;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeroCard(activeTask, isInProgress),
                const Gap(14),
                AbilityJobCard(taskId: widget.taskId),
                AccessAuditCard(task: activeTask),
                _buildActionsCard(activeTask),
                if (isInProgress &&
                    activeTask.needsCompletionProof &&
                    !activeTask.hasCompletionProof) ...[
                  const Gap(14),
                  _buildProofGate(activeTask),
                ],
                if (isInProgress && activeTask.hasCompletionProof) ...[
                  const Gap(14),
                  _SoftBanner(
                    icon: Icons.verified_rounded,
                    color: AppColors.helperAccent,
                    text: activeTask.requiresPurchaseProof
                        ? 'Proof submitted (${AppConfig.money(activeTask.goodsSpent)}). '
                            'Wait for client to check, then enter End OTP.'
                        : 'Completion proof submitted. Ask the client for End OTP.',
                  ),
                ],
                const Gap(14),
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
        },
      ),
    );
  }

  Widget _buildHeroCard(Task task, bool isInProgress) {
    final palette = ZivoPalette.of(context);
    final accent = isInProgress ? palette.accent : AppColors.uberBlue;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(
                    begin: const Offset(0.85, 0.85),
                    end: const Offset(1.3, 1.3),
                    duration: 900.ms,
                  ),
              const Gap(8),
              Expanded(
                child: Text(
                  isInProgress ? 'Underway' : 'Waiting for Start OTP',
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                    fontSize: 12,
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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: CategoryIcon(task.category, size: 18),
              ),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: AppTextStyles.headingSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.2,
                        color: palette.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Gap(3),
                    Text(
                      task.description,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textSecondary,
                        height: 1.3,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (task.photoUrls.isNotEmpty) ...[
            const Gap(8),
            TaskPhotoGallery(photoUrls: task.photoUrls, height: 72),
          ],
          const Gap(8),
          Text(
            [
              '${task.estimatedHours}h',
              '${AppConfig.money(task.totalAmount * 0.9)} earn',
              if (task.locationLabel != null) task.locationLabel!,
            ].join('  ·  '),
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 11,
              color: palette.textMuted,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.03, end: 0);
  }

  Widget _buildActionsCard(Task task) {
    return Row(
      children: [
        Expanded(
          child: ChatUnreadPoller(
            taskId: widget.taskId,
            builder: (context, unread) => _CompactAction(
              icon: Icons.chat_bubble_outline_rounded,
              label: unread > 0 ? 'Chat $unread' : 'Chat',
              tone: const Color(0xFF1D4ED8),
              onTap: () => context.push(
                AppRoutes.chatFor(widget.taskId, title: task.title),
              ),
            ),
          ),
        ),
        const Gap(8),
        Expanded(
          child: _CompactAction(
            icon: Icons.gavel_rounded,
            label: 'Trust',
            tone: AppColors.helperAccent,
            onTap: () => showTrustReviewSheet(context, taskId: widget.taskId),
          ),
        ),
      ],
    );
  }

  Widget _buildProofGate(Task task) {
    final grocery = task.requiresPurchaseProof;
    final palette = ZivoPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.warningColor.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.warningColor.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.warningColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.photo_camera_rounded,
                  color: AppColors.warningColor,
                  size: 20,
                ),
              ),
              const Gap(12),
              Expanded(
                child: Text(
                  grocery
                      ? 'Purchase proof required'
                      : 'Completion proof required',
                  style: AppTextStyles.headingSmall.copyWith(
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const Gap(10),
          Text(
            grocery
                ? 'Photograph the till receipt + bag. Never take cash from the client. '
                    'Budget ${AppConfig.money(task.goodsBudget)}.'
                : 'Check off the job list and add before/after photos. '
                    'End OTP stays locked until proof is submitted.',
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.textSecondary,
              height: 1.35,
            ),
          ),
          if (task.completionChecklist.isNotEmpty) ...[
            const Gap(10),
            ...task.completionChecklist.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check_box_outline_blank, size: 16),
                    const Gap(8),
                    Expanded(
                      child: Text(item, style: AppTextStyles.bodySmall),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const Gap(14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => grocery
                  ? _showProofDialog(task)
                  : _showCompletionProofDialog(task),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                grocery
                    ? 'Run receipt reconciliation'
                    : 'Submit completion proof',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCompletionProofDialog(Task task) async {
    final checklist = task.completionChecklist.isNotEmpty
        ? List<String>.from(task.completionChecklist)
        : <String>[
            'Before photo',
            'After photo',
            'Work area left tidy',
          ];
    final checked = <String>{};
    final photos = <List<int>>[];
    final noteCtrl = TextEditingController();
    var submitting = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Completion proof'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tick what you finished and add 1–3 photos.',
                      style: AppTextStyles.bodySmall,
                    ),
                    const Gap(12),
                    ...checklist.map(
                      (item) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: checked.contains(item),
                        title: Text(item, style: AppTextStyles.bodySmall),
                        onChanged: (v) => setLocal(() {
                          if (v == true) {
                            checked.add(item);
                          } else {
                            checked.remove(item);
                          }
                        }),
                      ),
                    ),
                    const Gap(8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        final file = await picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 75,
                          maxWidth: 1600,
                        );
                        if (file == null) return;
                        final bytes = await file.readAsBytes();
                        setLocal(() {
                          if (photos.length < 3) photos.add(bytes);
                        });
                      },
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: Text(
                        photos.isEmpty
                            ? 'Add photo'
                            : '${photos.length}/3 photos',
                      ),
                    ),
                    const Gap(8),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: submitting || checked.isEmpty
                      ? null
                      : () async {
                          setLocal(() => submitting = true);
                          try {
                            await context
                                .read<TaskRepository>()
                                .submitCompletionProof(
                                  taskId: task.id,
                                  checkedItems: checked.toList(),
                                  photoBytes: photos,
                                  note: noteCtrl.text.trim(),
                                );
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            setLocal(() => submitting = false);
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(humanizeError(e)),
                                backgroundColor: AppColors.errorColor,
                              ),
                            );
                          }
                        },
                  child: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit proof'),
                ),
              ],
            );
          },
        );
      },
    );
    noteCtrl.dispose();
    if (ok == true && mounted) {
      context.read<OtpBloc>().add(OtpSubscribeToTask(widget.taskId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completion proof submitted'),
          backgroundColor: AppColors.successColor,
        ),
      );
    }
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

  Widget _buildOtpInput({
    required OtpState state,
    required Task task,
    required bool isVerifying,
    required bool isInProgress,
    String? errorMessage,
  }) {
    final palette = ZivoPalette.of(context);
    final accentColor = isInProgress ? palette.accent : AppColors.uberBlue;
    final phaseLabel = isInProgress ? 'End OTP' : 'Start OTP';
    final instruction = isInProgress
        ? (task.needsCompletionProof && !task.hasCompletionProof
            ? (task.requiresPurchaseProof
                ? 'Upload supermarket receipt + bag photos first. End OTP is blocked until proof is submitted — never take cash from the client.'
                : 'Submit completion proof (checklist + photos) first. End OTP stays locked until then.')
            : (task.requiresPurchaseProof
                ? 'Enter the End OTP after the client checks goods vs receipt. Escrow then releases.'
                : 'Enter the End OTP after the client reviews your proof. Escrow then releases.'))
        : 'Enter the Start OTP shown on the client’s phone to begin.';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_rounded, size: 14, color: accentColor),
              const Gap(6),
              Text(
                phaseLabel,
                style: AppTextStyles.bodySmall.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                isInProgress ? '2/2' : '1/2',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const Gap(6),
          Text(
            instruction,
            style: AppTextStyles.bodySmall.copyWith(
              height: 1.3,
              fontSize: 12,
              color: palette.textSecondary,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const Gap(12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _otpLength,
              (i) => Padding(
                padding: EdgeInsets.only(right: i < _otpLength - 1 ? 8 : 0),
                child: _OtpBox(
                  controller: _otpControllers[i],
                  focusNode: _focusNodes[i],
                  nextFocus: i < _otpLength - 1 ? _focusNodes[i + 1] : null,
                  prevFocus: i > 0 ? _focusNodes[i - 1] : null,
                  accentColor: accentColor,
                ),
              ),
            ),
          ),
          if (errorMessage != null) ...[
            const Gap(10),
            _SoftBanner(
              icon: Icons.warning_rounded,
              color: AppColors.errorColor,
              text: errorMessage,
            ),
          ],
          const Gap(12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isVerifying ? null : () => _submitOtp(state),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(42),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              child: isVerifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      isInProgress
                          ? 'Verify End OTP'
                          : 'Verify Start OTP',
                      style: AppTextStyles.buttonLabel.copyWith(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 280.ms).slideY(begin: 0.03, end: 0);
  }
}

class _CompactAction extends StatelessWidget {
  const _CompactAction({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tone.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: tone),
              const Gap(6),
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: tone,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftBanner extends StatelessWidget {
  const _SoftBanner({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const Gap(8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: color,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
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
      width: 40,
      height: 46,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.number,
        maxLength: 1,
        textAlign: TextAlign.center,
        style: AppTextStyles.headingSmall.copyWith(
          color: accentColor,
          fontWeight: FontWeight.w800,
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1A1A1A)
              : AppColors.otpBoxBg,
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.borderColor, width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: accentColor, width: 2),
          ),
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

class _CompletedView extends StatelessWidget {
  const _CompletedView({required this.task, required this.onBack});
  final Task task;
  final Future<void> Function() onBack;

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
            )
                .animate()
                .scale(duration: 600.ms, curve: Curves.elasticOut)
                .fadeIn(duration: 300.ms),
            const Gap(24),
            Text('Job Complete!', style: AppTextStyles.headingLarge)
                .animate()
                .fadeIn(delay: 200.ms),
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
                color: AppColors.helperAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.helperAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  Text('You Earned', style: AppTextStyles.bodyMedium),
                  const Gap(4),
                  Text(
                    AppConfig.money(earnings),
                    style: AppTextStyles.moneyLarge
                        .copyWith(color: AppColors.helperAccent),
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(delay: 400.ms)
                .scale(begin: const Offset(0.8, 0.8)),
            const Gap(32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  context.read<TaskBloc>().syncDemoTaskStatus(
                        task.copyWith(
                          status: TaskStatus.completed,
                          completedAt: task.completedAt ?? DateTime.now(),
                        ),
                      );
                  await onBack();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.helperAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Back to Jobs',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ).animate().fadeIn(delay: 500.ms),
          ],
        ),
      ),
    );
  }
}
