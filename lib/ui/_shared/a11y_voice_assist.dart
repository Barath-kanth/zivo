import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/a11y/a11y_cubit.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/task/task_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/utils/auth_gate.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
import 'package:hyperlocal/core/utils/speak_text.dart';
import 'package:hyperlocal/core/utils/voice_recorder.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/models/task_status.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';

/// Spoken status lines for vision-impaired tracking.
String a11yStatusSpeech(Task task) {
  final name = task.helperProfile?['full_name']?.toString() ??
      task.helperProfile?['name']?.toString() ??
      'your helper';
  switch (task.status) {
    case TaskStatus.open:
      return 'Your request is posted. Looking for a nearby helper.';
    case TaskStatus.matched:
      return '$name is matched and coming to you. When they arrive, share the start code.';
    case TaskStatus.inProgress:
      return '$name has arrived and started the job. Stay available for updates.';
    case TaskStatus.completed:
      return 'Job finished. Escrow is released. Thank you.';
    case TaskStatus.cancelled:
      return 'This request was cancelled.';
    case TaskStatus.disputed:
      return 'There is a dispute open. Open the task for details.';
  }
}

/// Global Speak assistant — Start/Stop recording, posts help by voice.
Future<void> showA11yVoiceAssist(
  BuildContext context, {
  String lang = 'en',
}) async {
  // Enable accessibility automatically — blind users should not hunt Account.
  final a11y = context.read<A11yCubit>();
  if (!a11y.enabled) {
    await a11y.setEnabled(true);
  }

  if (!context.mounted) return;
  if (!await requireAuth(context, returnTo: AppRoutes.shell)) return;
  if (!context.mounted) return;

  await speakText(
    'Accessibility on. Tap Start recording, say what you need, then Stop recording. For example: I need to buy food and bring it here.',
  );

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _A11yVoiceAssistSheet(lang: lang),
  );
}

class _A11yVoiceAssistSheet extends StatefulWidget {
  const _A11yVoiceAssistSheet({required this.lang});
  final String lang;

  @override
  State<_A11yVoiceAssistSheet> createState() => _A11yVoiceAssistSheetState();
}

class _A11yVoiceAssistSheetState extends State<_A11yVoiceAssistSheet> {
  bool _busy = false;
  String? _statusLine;
  String? _heard;
  String? _draftTitle;
  String? _draftDesc;
  String? _taskId;
  Timer? _poll;
  TaskStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    recordingListenable.addListener(_onRec);
  }

  @override
  void dispose() {
    recordingListenable.removeListener(_onRec);
    _poll?.cancel();
    if (recordingListenable.value) {
      cancelVoiceRecording();
    }
    super.dispose();
  }

  void _onRec() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleRecord() async {
    if (_busy) return;
    if (recordingListenable.value) {
      await _stopAndProcess();
      return;
    }
    setState(() {
      _statusLine = 'Listening… say what you need';
      _heard = null;
      _draftTitle = null;
      _draftDesc = null;
    });
    try {
      await startVoiceRecording(maxDuration: const Duration(seconds: 30));
      await speakText('Listening. Speak now.');
    } catch (e) {
      if (!mounted) return;
      final msg = humanizeError(e);
      setState(() => _statusLine = msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.errorColor,
          duration: const Duration(seconds: 6),
        ),
      );
      await speakText(msg);
    }
  }

  Future<void> _stopAndProcess() async {
    setState(() {
      _busy = true;
      _statusLine = 'Processing your request…';
    });
    await speakText('Got it. Processing.');
    try {
      final clip = await stopVoiceRecording();
      if (!mounted) return;
      final suggestion =
          await context.read<TaskRepository>().suggestFromVoice(
                audioBytes: clip,
                lang: widget.lang,
              );
      if (!mounted) return;
      final transcript = suggestion['transcript']?.toString() ?? '';
      final title = suggestion['title']?.toString() ?? 'Quick help nearby';
      final description = suggestion['description']?.toString() ?? '';
      final categoryName = suggestion['category']?.toString() ?? 'errandRun';

      setState(() {
        _heard = transcript;
        _draftTitle = title;
        _draftDesc = description;
        _statusLine = 'Confirming order…';
      });

      final confirm =
          'OK. I heard: ${transcript.isEmpty ? title : transcript}. '
          'Posting $title. Order almost done.';
      await speakText(confirm);

      final auth = context.read<AuthBloc>().state;
      if (auth is! AuthAuthenticated) {
        throw StateError('Please sign in first.');
      }

      final category = TaskCategory.fromString(categoryName);
      final isGrocery = category == TaskCategory.groceryRun ||
          category == TaskCategory.errandRun;
      final task = Task(
        id: '',
        clientId: auth.profile.id,
        title: title,
        description: description.length >= 20
            ? description
            : '$description Please help with this request nearby.',
        category: category,
        estimatedHours: 1.0,
        hourlyRate: 2000,
        totalAmount: 2000,
        location: const LatLng(6.9271, 79.8612),
        locationLabel: 'Near me',
        locationAddress: 'Near me',
        status: TaskStatus.open,
        createdAt: DateTime.now(),
        goodsBudget: isGrocery ? 2500 : 0,
        requiresPurchaseProof: isGrocery,
      );

      final created = await context.read<TaskRepository>().createTask(task);
      if (!mounted) return;

      context.read<TaskBloc>().add(TaskFetchClientTasks(auth.profile.id));

      setState(() {
        _taskId = created.id;
        _lastStatus = created.status;
        _statusLine =
            'OK done — order posted (${AppConfig.money(created.totalAmount)}). Looking for a helper.';
        _busy = false;
      });

      await speakText(
        'OK done. Order done. Your request is posted. '
        'Looking for a nearby helper. I will tell you when someone is coming, and when they arrive.',
      );

      _startStatusPoll(created.id);
    } catch (e) {
      if (!mounted) return;
      final msg = humanizeError(e);
      setState(() {
        _busy = false;
        _statusLine = msg;
      });
      await speakText(msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    }
  }

  void _startStatusPoll(String taskId) {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!mounted) return;
      try {
        final task = await context.read<TaskRepository>().getTaskById(taskId);
        if (!mounted || task == null) return;
        if (_lastStatus == task.status) return;
        _lastStatus = task.status;
        final line = a11yStatusSpeech(task);
        setState(() => _statusLine = line);
        await speakText(line);
        if (task.status == TaskStatus.completed ||
            task.status == TaskStatus.cancelled) {
          _poll?.cancel();
        }
      } catch (_) {
        /* ignore poll errors */
      }
    });
  }

  Future<void> _readLatestStatus() async {
    final id = _taskId;
    if (id == null) {
      await speakText(
        'No active voice order yet. Tap Start recording and say what you need.',
      );
      return;
    }
    try {
      final task = await context.read<TaskRepository>().getTaskById(id);
      if (!mounted) return;
      if (task == null) {
        await speakText('Could not find that request.');
        return;
      }
      final line = a11yStatusSpeech(task);
      setState(() => _statusLine = line);
      await speakText(line);
    } catch (e) {
      await speakText(humanizeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final recording = recordingListenable.value;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const Gap(14),
            Text('Speak for help', style: AppTextStyles.headingMedium),
            const Gap(4),
            Text(
              'For blind and low-vision users: say what you need. '
              'We post the order and tell you when a helper is coming or has arrived.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textMuted,
                height: 1.35,
              ),
            ),
            const Gap(16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _toggleRecord,
                    icon: Icon(
                      recording ? Icons.stop_circle : Icons.mic_rounded,
                    ),
                    label: Text(
                      recording ? 'Stop recording' : 'Start recording',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          recording ? AppColors.errorColor : Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            if (recording) ...[
              const Gap(10),
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  Gap(8),
                  Text('Recording… tap Stop when finished'),
                ],
              ),
            ],
            if (_busy && !recording) ...[
              const Gap(10),
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  Gap(8),
                  Text('Working on your order…'),
                ],
              ),
            ],
            if (_statusLine != null) ...[
              const Gap(14),
              Material(
                color: AppColors.helperAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _statusLine!,
                    style: AppTextStyles.bodyMedium.copyWith(height: 1.4),
                  ),
                ),
              ),
              const Gap(8),
              TextButton.icon(
                onPressed: () {
                  if (speakingListenable.value) {
                    stopSpeaking();
                  } else {
                    speakText(_statusLine!);
                  }
                },
                icon: const Icon(Icons.volume_up_rounded, size: 18),
                label: const Text('Read aloud'),
              ),
            ],
            if (_heard != null && _heard!.isNotEmpty) ...[
              const Gap(8),
              Text(
                'Heard: “$_heard”',
                style: AppTextStyles.bodySmall.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (_draftTitle != null) ...[
              const Gap(8),
              Text(_draftTitle!, style: AppTextStyles.headingSmall),
              if (_draftDesc != null)
                Text(_draftDesc!, style: AppTextStyles.bodySmall),
            ],
            const Gap(12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _readLatestStatus,
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Where is my helper?'),
            ),
            if (_taskId != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/task/$_taskId/track');
                },
                child: const Text('Open request'),
              ),
            TextButton(
              onPressed: () {
                stopSpeaking();
                if (recordingListenable.value) cancelVoiceRecording();
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
