import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
import 'package:hyperlocal/core/utils/voice_recorder.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';

/// Persisted in-app chat between client and assigned helper for one task.
/// WhatsApp-style: failed sends stay as bubbles with a red ! and "Message not
/// sent" pill (no full-width red banner). Voice notes are available to everyone
/// and run through the same contact + vernacular safety path as typed text.
class TaskChatScreen extends StatefulWidget {
  const TaskChatScreen({
    super.key,
    required this.taskId,
    this.taskTitle,
  });

  final String taskId;
  final String? taskTitle;

  @override
  State<TaskChatScreen> createState() => _TaskChatScreenState();
}

class _TaskChatScreenState extends State<TaskChatScreen> {
  static const _voiceMax = Duration(seconds: 60);

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <Map<String, dynamic>>[];
  Timer? _poll;
  Timer? _taskPoll;
  Timer? _recTick;
  bool _loading = true;
  bool _sending = false;
  bool _recording = false;
  bool _recPaused = false;
  bool _transcribing = false;
  Duration _recElapsed = Duration.zero;
  String? _error;
  String? _myId;
  bool _readOnly = false;
  Task? _liveTask;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthBloc>().state;
    if (auth is AuthAuthenticated) _myId = auth.profile.id;
    _load(initial: true);
    _loadTask();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _load());
    // Fast task poll so client sees completion proof in chat without waiting.
    _taskPoll = Timer.periodic(const Duration(seconds: 2), (_) => _loadTask());
    recordingPausedListenable.addListener(_onPauseChanged);
  }

  void _onPauseChanged() {
    if (!mounted) return;
    setState(() => _recPaused = recordingPausedListenable.value);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _taskPoll?.cancel();
    _recTick?.cancel();
    recordingPausedListenable.removeListener(_onPauseChanged);
    if (_recording) {
      cancelVoiceRecording();
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadTask() async {
    try {
      final t =
          await context.read<TaskRepository>().getTaskById(widget.taskId);
      if (!mounted || t == null) return;
      final prev = _liveTask?.proofSubmittedAt;
      setState(() => _liveTask = t);
      // Once proof is in, slow the task poll — chat poll still runs.
      if (t.hasCompletionProof && prev == null) {
        _taskPoll?.cancel();
        _taskPoll =
            Timer.periodic(const Duration(seconds: 8), (_) => _loadTask());
      }
    } catch (_) {
      /* ignore — chat still works */
    }
  }

  Future<void> _markRead() async {
    try {
      await context.read<TaskRepository>().markTaskChatRead(widget.taskId);
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final after = (!initial && _messages.isNotEmpty)
          ? _messages
              .where((m) => m['failed'] != true)
              .map((m) => m['created_at']?.toString())
              .whereType<String>()
              .fold<String?>(null, (a, b) => a == null || b.compareTo(a) > 0 ? b : a)
          : null;
      final lang = _chatLang();
      final res = await context.read<TaskRepository>().getTaskChat(
            widget.taskId,
            afterIso: after,
            lang: lang,
          );
      if (!mounted) return;
      final list = ((res['messages'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        if (initial) {
          final failedLocals =
              _messages.where((m) => m['failed'] == true).toList();
          _messages
            ..clear()
            ..addAll(list)
            ..addAll(failedLocals);
        } else if (list.isNotEmpty) {
          final known = _messages.map((m) => m['id']).toSet();
          for (final m in list) {
            if (!known.contains(m['id'])) _messages.add(m);
          }
        }
        _loading = false;
        _error = null;
      });
      await _markRead();
      if (list.isNotEmpty || initial) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (initial) _error = '$e';
      });
    }
  }

  /// Chat only supports en/si/ta.
  String _chatLang() {
    final c = context.read<LocaleCubit>().code;
    return (c == 'si' || c == 'ta' || c == 'en') ? c : 'en';
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send({String? overrideText, bool viaVoice = false}) async {
    final text = (overrideText ?? _input.text).trim();
    if (text.isEmpty || _sending || _readOnly) return;
    setState(() => _sending = true);

    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final optimistic = <String, dynamic>{
      'id': localId,
      'sender_id': _myId,
      'sender_role': 'me',
      'body': text,
      'body_original': text,
      'display_body': text,
      'via_voice': viaVoice,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'pending': true,
    };
    setState(() {
      if (overrideText == null) _input.clear();
      _messages.add(optimistic);
    });
    _scrollToEnd();

    try {
      final lang = _chatLang();
      final res = await context.read<TaskRepository>().sendTaskChatMessage(
            taskId: widget.taskId,
            body: text,
            lang: lang,
            viaVoice: viaVoice,
          );
      if (!mounted) return;
      final msg = res['message'];
      setState(() {
        _messages.removeWhere((m) => m['id'] == localId);
        if (msg is Map) {
          _messages.add(Map<String, dynamic>.from(msg));
        }
        _sending = false;
      });
      _scrollToEnd();
      if (msg is! Map) await _load(initial: true);
    } catch (e) {
      if (!mounted) return;
      final msg = humanizeError(e).replaceFirst('Exception: ', '');
      final lower = msg.toLowerCase();
      final blocked = lower.contains('safety') ||
          lower.contains('community') ||
          lower.contains('doesn’t meet') ||
          lower.contains("doesn't meet") ||
          lower.contains('phone') ||
          lower.contains('whatsapp') ||
          lower.contains('email') ||
          lower.contains('not allowed') ||
          lower.contains('on zivo') ||
          lower.contains('blocked') ||
          lower.contains('voice note') ||
          lower.contains('abuse') ||
          lower.contains('respectful') ||
          lower.contains('drugs') ||
          lower.contains('violence');
      if (lower.contains('closed')) {
        setState(() => _readOnly = true);
      }
      setState(() {
        _sending = false;
        final i = _messages.indexWhere((m) => m['id'] == localId);
        if (i >= 0) {
          _messages[i] = {
            ..._messages[i],
            'pending': false,
            'failed': true,
            'fail_reason': msg,
            'blocked': blocked,
          };
        }
      });
      _scrollToEnd();
      // Pull system "blocked" notice for the other party + this thread.
      if (blocked) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (mounted) await _load();
      }
    }
  }

  void _startRecTicker() {
    _recTick?.cancel();
    _recElapsed = Duration.zero;
    _recTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_recording || _recPaused) return;
      setState(() {
        _recElapsed += const Duration(seconds: 1);
        if (_recElapsed >= _voiceMax) {
          _finishVoiceAndSend();
        }
      });
    });
  }

  Future<void> _beginVoice() async {
    if (_sending || _recording || _readOnly || _transcribing) return;
    try {
      await startVoiceRecording(maxDuration: _voiceMax);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recPaused = false;
        _recElapsed = Duration.zero;
      });
      _startRecTicker();
    } catch (e) {
      if (!mounted) return;
      setState(() => _recording = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanizeError(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _cancelVoice() async {
    _recTick?.cancel();
    await cancelVoiceRecording();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recPaused = false;
      _recElapsed = Duration.zero;
      _transcribing = false;
    });
  }

  Future<void> _togglePauseVoice() async {
    if (!_recording) return;
    if (_recPaused) {
      await resumeVoiceRecording();
    } else {
      await pauseVoiceRecording();
    }
    if (!mounted) return;
    setState(() => _recPaused = recordingPausedListenable.value);
  }

  Future<void> _finishVoiceAndSend() async {
    if (!_recording || _transcribing) return;
    _recTick?.cancel();
    setState(() => _transcribing = true);
    try {
      final clip = await stopVoiceRecording();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recPaused = false;
      });
      if (clip == null || clip.isEmpty) {
        setState(() => _transcribing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not hear that — try again'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final lang = _chatLang();
      final res = await context.read<TaskRepository>().a11yTranscribe(
            audioBytes: clip,
            lang: lang,
          );
      final transcript = res['transcript']?.toString().trim() ?? '';
      if (!mounted) return;
      setState(() => _transcribing = false);
      if (transcript.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not hear that — try again'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await _send(overrideText: transcript, viaVoice: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recPaused = false;
        _transcribing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanizeError(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatRecTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showFailDetail(String reason) {
    final palette = ZivoPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final p = ZivoPalette.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Gap(20),
              Row(
                children: [
                  const _FailDot(size: 22),
                  const Gap(10),
                  Text(
                    'Message not sent',
                    style: AppTextStyles.headingSmall.copyWith(
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary,
                    ),
                  ),
                ],
              ),
              const Gap(12),
              Text(
                reason,
                style: AppTextStyles.bodyMedium.copyWith(
                  height: 1.4,
                  color: p.textSecondary,
                ),
              ),
              const Gap(20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.taskTitle?.trim().isNotEmpty == true
        ? widget.taskTitle!
        : 'Job chat';
    final palette = ZivoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? palette.canvas : const Color(0xFFEFEAE2),
      appBar: AppBar(
        backgroundColor: palette.card,
        foregroundColor: palette.textPrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTextStyles.headingSmall.copyWith(
                color: palette.textPrimary,
              ),
            ),
            Text(
              'In-app only · saved with this job',
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 11,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: palette.textPrimary,
          ),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? palette.card
                  : AppColors.borderColor.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: Text(
              'In-app chat only — every message is safety-checked and saved as evidence. Don’t share phone numbers or move off Zivo.',
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 11,
                height: 1.35,
                color: palette.textSecondary,
              ),
            ),
          ),
          if (_liveTask != null && _liveTask!.hasCompletionProof)
            _ChatProofBanner(task: _liveTask!),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.accent,
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!.replaceFirst('Exception: ', ''),
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          return _Bubble(
                            message: m,
                            mine: m['sender_id']?.toString() == _myId ||
                                m['sender_role']?.toString() == 'me',
                            onFailTap: m['failed'] == true
                                ? () => _showFailDetail(
                                      m['fail_reason']?.toString() ??
                                          'Message not sent',
                                    )
                                : null,
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: palette.card,
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
              child: _recording || _transcribing
                  ? _WhatsAppRecordBar(
                      elapsedLabel: _formatRecTime(_recElapsed),
                      paused: _recPaused,
                      busy: _transcribing,
                      onCancel: _transcribing ? null : _cancelVoice,
                      onPause: _transcribing ? null : _togglePauseVoice,
                      onSend: _transcribing ? null : _finishVoiceAndSend,
                    )
                  : Row(
                      children: [
                        IconButton(
                          tooltip:
                              'Voice message — available to everyone; safety-checked like text',
                          onPressed:
                              (_sending || _readOnly) ? null : _beginVoice,
                          icon: Icon(
                            Icons.mic_none_rounded,
                            color: isDark
                                ? palette.accent
                                : AppColors.helperAccent,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _input,
                            enabled: !_readOnly,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            // Explicit ink — theme textColor alone was white on light fill.
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: palette.textPrimary,
                            ),
                            cursorColor: palette.accent,
                            decoration: InputDecoration(
                              hintText: _readOnly
                                  ? 'Chat closed for this job'
                                  : 'Message the other party…',
                              hintStyle: AppTextStyles.bodyMedium.copyWith(
                                color: palette.textMuted,
                              ),
                              isDense: true,
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF2A2A2A)
                                  : const Color(0xFFF5F5F5),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide(
                                  color: palette.border,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide(
                                  color: palette.border,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide(
                                  color: palette.accent,
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const Gap(8),
                        IconButton.filled(
                          onPressed:
                              (_sending || _readOnly) ? null : () => _send(),
                          style: IconButton.styleFrom(
                            backgroundColor: isDark
                                ? palette.accent
                                : AppColors.helperAccent,
                            foregroundColor: Colors.white,
                          ),
                          icon: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 20),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// WhatsApp-style inline recorder: trash · red dot+timer · waveform · pause · send.
class _WhatsAppRecordBar extends StatelessWidget {
  const _WhatsAppRecordBar({
    required this.elapsedLabel,
    required this.paused,
    required this.busy,
    required this.onCancel,
    required this.onPause,
    required this.onSend,
  });

  final String elapsedLabel;
  final bool paused;
  final bool busy;
  final VoidCallback? onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F8),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Delete',
            onPressed: onCancel,
            icon: Icon(
              Icons.delete_outline_rounded,
              color: onCancel == null
                  ? Colors.black26
                  : const Color(0xFF667781),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: paused || busy
                  ? const Color(0xFFB0B0B0)
                  : const Color(0xFFE53935),
              shape: BoxShape.circle,
            ),
          ),
          const Gap(8),
          SizedBox(
            width: 40,
            child: Text(
              elapsedLabel,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3B4A54),
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const Gap(6),
          Expanded(
            child: busy
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : ValueListenableBuilder<List<double>>(
                    valueListenable: recordingLevelsListenable,
                    builder: (context, levels, _) {
                      return SizedBox(
                        height: 28,
                        width: double.infinity,
                        child: CustomPaint(
                          painter:
                              _WavePainter(levels: levels, paused: paused),
                        ),
                      );
                    },
                  ),
          ),
          const Gap(4),
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 0.5,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPause,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: onPause == null
                      ? Colors.black26
                      : const Color(0xFF111B21),
                  size: 22,
                ),
              ),
            ),
          ),
          const Gap(6),
          Material(
            color: AppColors.helperAccent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onSend,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.send_rounded,
                  color: onSend == null ? Colors.white54 : Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
          const Gap(4),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.levels, required this.paused});
  final List<double> levels;
  final bool paused;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty || size.width <= 0) return;
    final paint = Paint()
      ..color = paused ? const Color(0xFFB0BEC5) : const Color(0xFF8696A0)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final n = levels.length;
    final gap = size.width / n;
    final mid = size.height / 2;
    for (var i = 0; i < n; i++) {
      final h = (levels[i].clamp(0.06, 1.0)) * (size.height * 0.9);
      final x = i * gap + gap / 2;
      canvas.drawLine(
        Offset(x, mid - h / 2),
        Offset(x, mid + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.levels != levels || oldDelegate.paused != paused;
}

class _FailDot extends StatelessWidget {
  const _FailDot({this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFE53935),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '!',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.55,
          height: 1,
        ),
      ),
    );
  }
}

class _Bubble extends StatefulWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    this.onFailTap,
  });
  final Map<String, dynamic> message;
  final bool mine;
  final VoidCallback? onFailTap;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  /// Default = original language. Tap flips to translation when available.
  bool _showTranslation = false;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final mine = widget.mine;
    final role = message['sender_role']?.toString() ?? '';
    final failed = message['failed'] == true;
    final pending = message['pending'] == true;
    final viaVoice = message['via_voice'] == true;
    final original =
        (message['body_original'] ?? message['display_body'] ?? message['body'])
                ?.toString() ??
            '';
    final translation = message['translation_body']?.toString();
    final translated = message['translated'] == true &&
        translation != null &&
        translation.isNotEmpty &&
        translation != original;
    final sourceLang = message['source_lang']?.toString();
    final body =
        _showTranslation && translated ? translation! : original;
    final at = message['created_at']?.toString();
    String time = '';
    if (at != null) {
      final dt = DateTime.tryParse(at)?.toLocal();
      if (dt != null) {
        final h = dt.hour;
        final m = dt.minute.toString().padLeft(2, '0');
        final ampm = h >= 12 ? 'PM' : 'AM';
        final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
        time = '$h12:$m $ampm';
      }
    }

    if (role == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8E6E1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 11,
                height: 1.35,
                color: const Color(0xFF54656F),
              ),
            ),
          ),
        ),
      );
    }

    final bubbleColor = mine
        ? (failed ? const Color(0xFFDCF8C6) : const Color(0xFFDCF8C6))
        : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: GestureDetector(
                  onTap: translated && !failed
                      ? () => setState(
                            () => _showTranslation = !_showTranslation,
                          )
                      : (failed ? widget.onFailTap : null),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: Radius.circular(mine ? 12 : 4),
                        bottomRight: Radius.circular(mine ? 4 : 12),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: mine
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (viaVoice) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.mic_rounded,
                                size: 14,
                                color: Colors.black.withValues(alpha: 0.45),
                              ),
                              const Gap(4),
                              Text(
                                'Voice note',
                                style: AppTextStyles.bodySmall.copyWith(
                                  fontSize: 10,
                                  color: Colors.black.withValues(alpha: 0.45),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const Gap(4),
                        ],
                        Text(
                          body,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: const Color(0xFF111B21),
                            height: 1.35,
                          ),
                        ),
                        if (translated && !failed) ...[
                          const Gap(4),
                          Text(
                            _showTranslation
                                ? 'Translation · tap for original${sourceLang != null ? ' ($sourceLang)' : ''}'
                                : 'Original${sourceLang != null ? ' ($sourceLang)' : ''} · tap for translation',
                            style: AppTextStyles.bodySmall.copyWith(
                              fontSize: 10,
                              color: Colors.black.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                        const Gap(2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (pending) ...[
                              SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.black.withValues(alpha: 0.35),
                                ),
                              ),
                              const Gap(4),
                            ],
                            if (time.isNotEmpty)
                              Text(
                                time,
                                style: AppTextStyles.bodySmall.copyWith(
                                  fontSize: 10,
                                  color: Colors.black.withValues(alpha: 0.45),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (failed && mine) ...[
                const Gap(6),
                GestureDetector(
                  onTap: widget.onFailTap,
                  child: const _FailDot(),
                ),
              ],
            ],
          ),
          if (failed && mine) ...[
            const Gap(6),
            GestureDetector(
              onTap: widget.onFailTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FailDot(size: 14),
                    Gap(6),
                    Text(
                      'Message not sent',
                      style: TextStyle(
                        color: Color(0xFFC62828),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Sticky proof strip so client sees checklist + photos in chat immediately.
class _ChatProofBanner extends StatelessWidget {
  const _ChatProofBanner({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.successColor.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified_outlined,
                  size: 16,
                  color: AppColors.successColor,
                ),
                const Gap(8),
                Expanded(
                  child: Text(
                    'Completion proof ready — review then share End OTP',
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppColors.successColor,
                    ),
                  ),
                ),
              ],
            ),
            if (task.proofCheckedItems.isNotEmpty) ...[
              const Gap(6),
              ...task.proofCheckedItems.take(4).map(
                    (item) => Text(
                      '✓ $item',
                      style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
                    ),
                  ),
            ],
            if (task.proofPhotoUrls.isNotEmpty) ...[
              const Gap(8),
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: task.proofPhotoUrls.length.clamp(0, 3),
                  separatorBuilder: (_, __) => const Gap(6),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      task.proofPhotoUrls[i],
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 48,
                        height: 48,
                        color: AppColors.borderColor,
                        child: const Icon(Icons.image_outlined, size: 16),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
