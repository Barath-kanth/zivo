import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/task/task_bloc.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
import 'package:hyperlocal/core/utils/voice_recorder.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';

/// One neighbourhood problem → several related jobs (bundle checkout).
///
/// When [autoPlan] is true (voice agent), planning starts immediately.
Future<void> showTaskBundlePlanner(
  BuildContext context, {
  String? initialProblem,
  String? categoryHint,
  String? bookedForName,
  String? bookedForUserId,
  bool autoPlan = false,
  String? heardTranscript,
  /// Voice agent: the sheet opens at once and shows live progress while this resolves.
  Future<Map<String, dynamic>>? voicePlan,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: ZivoPalette.of(context).card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _TaskBundleSheet(
      initialProblem: initialProblem ?? '',
      categoryHint: categoryHint,
      bookedForName: bookedForName,
      bookedForUserId: bookedForUserId,
      autoPlan: autoPlan,
      heardTranscript: heardTranscript,
      voicePlan: voicePlan,
    ),
  );
}

class _TaskBundleSheet extends StatefulWidget {
  const _TaskBundleSheet({
    required this.initialProblem,
    this.categoryHint,
    this.bookedForName,
    this.bookedForUserId,
    this.autoPlan = false,
    this.heardTranscript,
    this.voicePlan,
  });

  final Future<Map<String, dynamic>>? voicePlan;
  final String initialProblem;
  final String? categoryHint;
  final String? bookedForName;
  final String? bookedForUserId;
  final bool autoPlan;
  final String? heardTranscript;

  @override
  State<_TaskBundleSheet> createState() => _TaskBundleSheetState();
}

class _TaskBundleSheetState extends State<_TaskBundleSheet> {
  late final TextEditingController _problemCtrl;
  bool _planning = false;
  bool _checkingOut = false;
  String? _bundleTitle;
  String? _explanation;
  List<Map<String, dynamic>> _drafts = const [];
  final Set<int> _selected = {};
  /// 0 = describe, 1 = pick pieces, 2 = confirm
  int _phase = 0;

  static const _palette = [
    Color(0xFF0F766E),
    Color(0xFFBE185D),
    Color(0xFFB54708),
    Color(0xFF1D4ED8),
    AppColors.brandPurple,
  ];

  @override
  void initState() {
    super.initState();
    _problemCtrl = TextEditingController(text: widget.initialProblem);
    if (widget.voicePlan != null) {
      _awaitVoicePlan(widget.voicePlan!);
    } else if (widget.autoPlan && widget.initialProblem.trim().length >= 12) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _plan();
      });
    }
  }

  // ── Voice agent: one server call, live stages ─────────────────────────
  bool _agentPending = false;
  int _agentStage = 0;
  int _agentSeconds = 0;
  String? _agentHeard;
  Timer? _agentTimer;

  void _awaitVoicePlan(Future<Map<String, dynamic>> f) {
    _agentPending = true;
    _agentTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _agentSeconds = t.tick;
        // Stages are honest progress markers: audio is uploaded → model is working → plan arrives.
        _agentStage = t.tick < 2 ? 0 : (t.tick < 5 ? 1 : 2);
      });
    });
    f.then((res) {
      if (!mounted) return;
      _agentTimer?.cancel();
      final l = context.read<LocaleCubit>();
      final transcript = res['transcript']?.toString().trim() ?? '';
      final tasks = (res['tasks'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      setState(() {
        _agentPending = false;
        _agentHeard = transcript.isEmpty ? null : transcript;
        if (transcript.isNotEmpty) _problemCtrl.text = transcript;
        if (tasks.isNotEmpty) {
          _bundleTitle = res['bundle_title']?.toString() ?? l.t('split.bundle');
          _explanation = res['plan_explanation']?.toString();
          _drafts = tasks;
          _selected
            ..clear()
            ..addAll(List.generate(tasks.length, (i) => i));
          _phase = 1;
        }
      });
      if (tasks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.t('create.agentNeedMore'))),
        );
      }
    }).catchError((Object e) {
      if (!mounted) return;
      _agentTimer?.cancel();
      setState(() => _agentPending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanizeError(e)),
          backgroundColor: AppColors.errorColor,
        ),
      );
    });
  }

  @override
  void dispose() {
    _agentTimer?.cancel();
    _problemCtrl.dispose();
    super.dispose();
  }

  Future<void> _plan() async {
    final l = context.read<LocaleCubit>();
    final problem = _problemCtrl.text.trim();
    if (problem.length < 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.t('split.needMore'))),
      );
      return;
    }
    setState(() => _planning = true);
    try {
      final res = await context.read<TaskRepository>().planTaskBundle(
            problem: problem,
            categoryHint: widget.categoryHint,
            lang: 'auto',
          );
      if (!mounted) return;
      final tasks = (res['tasks'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      setState(() {
        _planning = false;
        _bundleTitle = res['bundle_title']?.toString() ?? l.t('split.bundle');
        _explanation = res['explanation']?.toString();
        _drafts = tasks;
        _selected
          ..clear()
          ..addAll(List.generate(tasks.length, (i) => i));
        _phase = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _planning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanizeError(e)),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  Future<void> _checkout() async {
    final l = context.read<LocaleCubit>();
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.t('split.pickOne'))),
      );
      return;
    }
    setState(() => _checkingOut = true);
    try {
      final tasks = _selected.map((i) {
        final t = _drafts[i];
        return {
          'title': t['title'],
          'description': t['description'],
          'category': t['category'],
          'estimated_hours': (t['estimated_hours'] as num?)?.toDouble() ?? 1,
          'goods_budget': (t['goods_budget'] as num?)?.toDouble() ?? 0,
        };
      }).toList();

      final deadline = DateTime.now()
          .add(const Duration(hours: 48))
          .toUtc()
          .toIso8601String();

      final res = await context.read<TaskRepository>().checkoutTaskBundle(
            bundleTitle: _bundleTitle ?? l.t('split.bundle'),
            lat: 6.9271,
            lon: 79.8612,
            locationLabel: 'Near me',
            deadlineAt: deadline,
            tasks: tasks,
            bookedForName: widget.bookedForName,
            bookedForUserId: widget.bookedForUserId,
          );
      if (!mounted) return;

      final auth = context.read<AuthBloc>().state;
      if (auth is AuthAuthenticated) {
        context.read<TaskBloc>().add(TaskFetchClientTasks(auth.profile.id));
      }

      final hold = res['total_hold_lkr'];
      final count = (res['tasks'] as List?)?.length ?? tasks.length;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${l.t('split.posted')} · $count · ${AppConfig.money(num.tryParse('$hold') ?? 0)}',
          ),
          backgroundColor: AppColors.successColor,
        ),
      );
      context.go(AppRoutes.shell);
    } catch (e) {
      if (!mounted) return;
      setState(() => _checkingOut = false);
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
    final l = context.watch<LocaleCubit>();
    final bottom = MediaQuery.paddingOf(context).bottom;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height;

    return SizedBox(
      height: height * 0.92,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + bottom + viewInsets),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: l.t('care.back'),
                  onPressed: () {
                    if (_phase > 0) {
                      setState(() => _phase -= 1);
                      return;
                    }
                    Navigator.of(context, rootNavigator: true).pop();
                  },
                  icon: Icon(
                    _phase == 0
                        ? Icons.close_rounded
                        : Icons.arrow_back_rounded,
                    color: ZivoPalette.of(context).textPrimary,
                  ),
                ),
                Expanded(
                  child: Text(
                    l.t('split.title'),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headingSmall.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ZivoPalette.of(context).textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const Gap(4),
            _PhaseDots(phase: _phase),
            const Gap(12),
            Expanded(
              child: AnimatedSwitcher(
                duration: 280.ms,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: switch (_phase) {
                  0 when _agentPending => _AgentProgress(
                      key: const ValueKey('agent'),
                      stage: _agentStage,
                      seconds: _agentSeconds,
                    ),
                  0 => _DescribePhase(
                      key: const ValueKey('describe'),
                      controller: _problemCtrl,
                      bookedForName: widget.bookedForName,
                      planning: _planning,
                      onPlan: _plan,
                      heardTranscript: _agentHeard ?? widget.heardTranscript,
                      autoPlan: widget.autoPlan,
                    ),
                  1 => _PickPhase(
                      key: const ValueKey('pick'),
                      title: _bundleTitle ?? l.t('split.bundle'),
                      explanation: _explanation,
                      drafts: _drafts,
                      selected: _selected,
                      palette: _palette,
                      onToggle: (i) {
                        setState(() {
                          if (_selected.contains(i)) {
                            _selected.remove(i);
                          } else {
                            _selected.add(i);
                          }
                        });
                      },
                      onContinue: _selected.isEmpty
                          ? null
                          : () => setState(() => _phase = 2),
                    ),
                  _ => _ConfirmPhase(
                      key: const ValueKey('confirm'),
                      title: _bundleTitle ?? l.t('split.bundle'),
                      drafts: [
                        for (final i in _selected.toList()..sort()) _drafts[i],
                      ],
                      palette: _palette,
                      checkingOut: _checkingOut,
                      onCheckout: _checkout,
                    ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown the instant the user stops speaking: real stages + elapsed time, never a blank spinner.
class _AgentProgress extends StatelessWidget {
  const _AgentProgress({super.key, required this.stage, required this.seconds});
  final int stage;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final steps = [
      l.t('split.stage.hear'),
      l.t('split.stage.understand'),
      l.t('split.stage.split'),
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.helperAccent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.smart_toy_rounded,
                color: AppColors.helperAccent,
                size: 38,
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  begin: const Offset(0.94, 0.94),
                  end: const Offset(1.06, 1.06),
                  duration: 900.ms,
                ),
            const Gap(22),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (i < stage)
                      const Icon(Icons.check_circle_rounded,
                          color: AppColors.helperAccent, size: 20)
                    else if (i == stage)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    else
                      const Icon(Icons.radio_button_unchecked_rounded,
                          color: Color(0xFFBBBBBB), size: 20),
                    const Gap(10),
                    Flexible(
                      child: Text(
                        steps[i],
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight:
                              i == stage ? FontWeight.w800 : FontWeight.w500,
                          color: i > stage
                              ? ZivoPalette.of(context).textMuted
                              : ZivoPalette.of(context).textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (seconds >= 8) ...[
              const Gap(16),
              Text(
                l.t('split.stage.slow'),
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: ZivoPalette.of(context).textMuted,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhaseDots extends StatelessWidget {
  const _PhaseDots({required this.phase});
  final int phase;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final palette = ZivoPalette.of(context);
    final labels = [
      l.t('split.phaseTell'),
      l.t('split.phasePick'),
      l.t('split.phasePost'),
    ];
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: i <= phase ? AppColors.helperAccent : palette.border,
              ),
            ),
          Column(
            children: [
              AnimatedContainer(
                duration: 220.ms,
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i <= phase
                      ? AppColors.helperAccent
                      : palette.border,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: i <= phase ? Colors.white : palette.textMuted,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const Gap(4),
              Text(
                labels[i],
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 11,
                  fontWeight: i == phase ? FontWeight.w800 : FontWeight.w500,
                  color: i == phase
                      ? palette.textPrimary
                      : palette.textMuted,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DescribePhase extends StatefulWidget {
  const _DescribePhase({
    super.key,
    required this.controller,
    required this.planning,
    required this.onPlan,
    this.bookedForName,
    this.heardTranscript,
    this.autoPlan = false,
    this.onHeard,
  });

  final TextEditingController controller;
  final bool planning;
  final VoidCallback onPlan;
  final String? bookedForName;
  final String? heardTranscript;
  final bool autoPlan;
  final void Function(String transcript)? onHeard;

  @override
  State<_DescribePhase> createState() => _DescribePhaseState();
}

class _DescribePhaseState extends State<_DescribePhase> {
  bool _listening = false;
  bool _busy = false;
  String? _localHeard;

  @override
  void initState() {
    super.initState();
    _localHeard = widget.heardTranscript;
    recordingListenable.addListener(_syncMic);
  }

  @override
  void dispose() {
    recordingListenable.removeListener(_syncMic);
    if (_listening || recordingListenable.value) {
      // Best-effort release mic if sheet closes mid-record.
      stopVoiceRecording();
    }
    super.dispose();
  }

  void _syncMic() {
    if (!mounted) return;
    if (!recordingListenable.value && _listening && !_busy) {
      setState(() => _listening = false);
    }
  }

  Future<void> _toggleVoice() async {
    if (_busy || widget.planning) return;
    final l = context.read<LocaleCubit>();

    if (_listening || recordingListenable.value) {
      setState(() => _busy = true);
      try {
        final clip = await stopVoiceRecording();
        if (!mounted) return;
        if (clip == null || clip.isEmpty) {
          setState(() {
            _listening = false;
            _busy = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.t('create.agentNeedMore'))),
          );
          return;
        }

        final suggestion =
            await context.read<TaskRepository>().suggestFromVoice(
                  audioBytes: clip,
                  lang: 'auto',
                );
        if (!mounted) return;

        final transcript = suggestion['transcript']?.toString().trim() ?? '';
        final title = suggestion['title']?.toString().trim() ?? '';
        final description = suggestion['description']?.toString().trim() ?? '';
        final seed = [
          if (transcript.isNotEmpty) transcript,
          if (title.isNotEmpty) title,
          if (description.isNotEmpty) description,
        ].join('. ');

        final text = seed.length >= 12
            ? seed
            : (description.isNotEmpty
                ? description
                : (title.isNotEmpty ? title : transcript));

        setState(() {
          _listening = false;
          _busy = false;
          if (transcript.isNotEmpty) _localHeard = transcript;
        });

        if (text.trim().length < 12) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.t('create.agentNeedMore'))),
          );
          return;
        }

        widget.controller.text = text.trim();
        widget.onHeard?.call(transcript);
        // Auto-suggest related jobs after voice understanding.
        widget.onPlan();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _busy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(humanizeError(e)),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
      return;
    }

    setState(() => _listening = true);
    try {
      await startVoiceRecording(maxDuration: const Duration(seconds: 60));
      if (!mounted) return;
      if (!recordingListenable.value && _listening) {
        setState(() => _listening = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _listening = false);
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
    final l = context.watch<LocaleCubit>();
    final palette = ZivoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heard = (_localHeard ?? widget.heardTranscript)?.trim();
    final locked = widget.planning || _busy;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.helperAccent.withValues(alpha: 0.14)
                  : null,
              gradient: isDark
                  ? null
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFE8F5F0), Color(0xFFF7F3EA)],
                    ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? AppColors.helperAccent.withValues(alpha: 0.35)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.helperAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.autoPlan || _busy
                        ? Icons.smart_toy_rounded
                        : Icons.auto_awesome_mosaic_rounded,
                    color: AppColors.helperAccent,
                    size: 28,
                  )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .rotate(begin: -0.03, end: 0.03, duration: 1600.ms),
                ),
                const Gap(14),
                Expanded(
                  child: Text(
                    widget.autoPlan || _busy
                        ? l.t('split.agentHero')
                        : l.t('split.hero'),
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (heard != null && heard.isNotEmpty) ...[
            const Gap(12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF242424) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.border),
              ),
              child: Text(
                '${l.t('split.heard')}: “$heard”',
                style: AppTextStyles.bodySmall.copyWith(
                  fontStyle: FontStyle.italic,
                  height: 1.35,
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],
          if (widget.bookedForName != null) ...[
            const Gap(10),
            Text(
              '${l.t('split.bookingFor')} ${widget.bookedForName}',
              style: AppTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.helperAccent,
              ),
            ),
          ],
          const Gap(14),
          TextField(
            controller: widget.controller,
            maxLines: 4,
            readOnly: locked,
            style: AppTextStyles.bodyMedium.copyWith(color: palette.textPrimary),
            decoration: InputDecoration(
              labelText: l.t('split.problemLabel'),
              hintText: l.t('split.problemHint'),
              labelStyle: TextStyle(color: palette.textSecondary),
              hintStyle: TextStyle(color: palette.textMuted),
              filled: true,
              fillColor: isDark ? const Color(0xFF2A2A2A) : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.accent, width: 1.5),
              ),
              alignLabelWithHint: true,
            ),
          ),
          const Gap(14),
          FilledButton.icon(
            onPressed: locked ? null : widget.onPlan,
            icon: widget.planning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              widget.planning
                  ? l.t('split.planning')
                  : (widget.autoPlan
                      ? l.t('split.suggestAgain')
                      : l.t('split.suggest')),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? palette.accent : Colors.black,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const Gap(12),
          // Voice agent under Suggest related jobs — any language.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.helperAccent.withValues(alpha: isDark ? 0.14 : 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.helperAccent.withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.helperAccent.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.smart_toy_rounded,
                        color: AppColors.helperAccent,
                        size: 22,
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.t('create.speak'),
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w800,
                              color: palette.textPrimary,
                            ),
                          ),
                          Text(
                            l.t('split.voiceUnderSuggest'),
                            style: AppTextStyles.bodySmall.copyWith(
                              color: palette.textSecondary,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Gap(10),
                if (!_listening && !_busy)
                  FilledButton.icon(
                    onPressed: widget.planning ? null : _toggleVoice,
                    icon: const Icon(Icons.mic_rounded, size: 18),
                    label: Text(l.t('create.startRec')),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.helperAccent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                else if (_listening && !_busy)
                  FilledButton.icon(
                    onPressed: _toggleVoice,
                    icon: const Icon(Icons.stop_circle, size: 18),
                    label: Text(l.t('create.stopRec')),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.errorColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: null,
                    icon: const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    label: Text(l.t('create.agentWorking')),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.helperAccent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                if (_listening && !_busy) ...[
                  const Gap(8),
                  Text(
                    l.t('create.agentListening'),
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.errorColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickPhase extends StatelessWidget {
  const _PickPhase({
    super.key,
    required this.title,
    required this.explanation,
    required this.drafts,
    required this.selected,
    required this.palette,
    required this.onToggle,
    required this.onContinue,
  });

  final String title;
  final String? explanation;
  final List<Map<String, dynamic>> drafts;
  final Set<int> selected;
  final List<Color> palette;
  final void Function(int) onToggle;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: AppTextStyles.headingSmall.copyWith(fontWeight: FontWeight.w800),
        ),
        if (explanation != null) ...[
          const Gap(4),
          Text(
            explanation!,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textMuted,
              height: 1.35,
            ),
          ),
        ],
        const Gap(8),
        Text(
          l.t('split.tapPieces'),
          style: AppTextStyles.bodySmall.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.helperAccent,
          ),
        ),
        const Gap(10),
        Expanded(
          child: ListView.separated(
            itemCount: drafts.length,
            separatorBuilder: (_, __) => const Gap(10),
            itemBuilder: (_, i) {
              final t = drafts[i];
              final on = selected.contains(i);
              final color = palette[i % palette.length];
              return Material(
                color: on ? color.withValues(alpha: 0.1) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onToggle(i),
                  child: AnimatedContainer(
                    duration: 200.ms,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: on ? color : AppColors.borderColor,
                        width: on ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (i < drafts.length - 1)
                              Container(
                                width: 2,
                                height: 28,
                                margin: const EdgeInsets.only(top: 4),
                                color: color.withValues(alpha: 0.35),
                              ),
                          ],
                        ),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t['title']?.toString() ?? 'Task',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Gap(4),
                              Text(
                                t['description']?.toString() ?? '',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textMuted,
                                  height: 1.3,
                                ),
                              ),
                              const Gap(8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _MiniChip(
                                    t['category']?.toString() ?? '',
                                    color,
                                  ),
                                  _MiniChip(
                                    '~${t['estimated_hours']}h',
                                    color,
                                  ),
                                  if (((t['goods_budget'] as num?) ?? 0) > 0)
                                    _MiniChip(
                                      AppConfig.money(
                                        t['goods_budget'] as num,
                                      ),
                                      color,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Gap(8),
                        Icon(
                          on
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: on ? color : AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: (60 * i).ms).slideX(begin: 0.04, end: 0);
            },
          ),
        ),
        const Gap(10),
        FilledButton(
          onPressed: onContinue,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.helperAccent,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
          ),
          child: Text(
            '${l.t('split.continue')} (${selected.length})',
          ),
        ),
      ],
    );
  }
}

class _ConfirmPhase extends StatelessWidget {
  const _ConfirmPhase({
    super.key,
    required this.title,
    required this.drafts,
    required this.palette,
    required this.checkingOut,
    required this.onCheckout,
  });

  final String title;
  final List<Map<String, dynamic>> drafts;
  final List<Color> palette;
  final bool checkingOut;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.t('split.ready'),
          style: AppTextStyles.headingSmall.copyWith(fontWeight: FontWeight.w800),
        ),
        const Gap(4),
        Text(
          title,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.helperAccent,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Gap(12),
        Expanded(
          child: ListView.separated(
            itemCount: drafts.length,
            separatorBuilder: (_, __) => const Gap(8),
            itemBuilder: (_, i) {
              final t = drafts[i];
              final color = palette[i % palette.length];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                  color: color.withValues(alpha: 0.06),
                ),
                child: Row(
                  children: [
                    Icon(Icons.task_alt_rounded, color: color),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        t['title']?.toString() ?? '',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const Gap(10),
        FilledButton(
          onPressed: checkingOut ? null : onCheckout,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
          ),
          child: Text(
            checkingOut
                ? l.t('split.checkingOut')
                : '${l.t('split.checkout')} (${drafts.length})',
          ),
        ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
