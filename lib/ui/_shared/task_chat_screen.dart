import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/ui/_shared/a11y_widgets.dart';

/// Persisted in-app chat between client and assigned helper for one task.
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
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <Map<String, dynamic>>[];
  Timer? _poll;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _myId;
  bool _readOnly = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthBloc>().state;
    if (auth is AuthAuthenticated) _myId = auth.profile.id;
    _load(initial: true);
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final after = (!initial && _messages.isNotEmpty)
          ? _messages.last['created_at']?.toString()
          : null;
      final res = await context.read<TaskRepository>().getTaskChat(
            widget.taskId,
            afterIso: after,
          );
      if (!mounted) return;
      final list = ((res['messages'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        if (initial) {
          _messages
            ..clear()
            ..addAll(list);
        } else if (list.isNotEmpty) {
          final known = _messages.map((m) => m['id']).toSet();
          for (final m in list) {
            if (!known.contains(m['id'])) _messages.add(m);
          }
        }
        _loading = false;
        _error = null;
      });
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _readOnly) return;
    setState(() => _sending = true);
    try {
      final res = await context.read<TaskRepository>().sendTaskChatMessage(
            taskId: widget.taskId,
            body: text,
          );
      if (!mounted) return;
      final msg = res['message'];
      if (msg is Map) {
        setState(() {
          _messages.add(Map<String, dynamic>.from(msg));
          _input.clear();
          _sending = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      } else {
        setState(() => _sending = false);
        await _load(initial: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      final msg = '$e'.replaceFirst('Exception: ', '');
      if (msg.toLowerCase().contains('closed')) {
        setState(() => _readOnly = true);
      }
      final blocked = msg.toLowerCase().contains('safety') ||
          msg.toLowerCase().contains('community') ||
          msg.toLowerCase().contains('doesn’t meet') ||
          msg.toLowerCase().contains("doesn't meet");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? 'Blocked by chat safety — keep it ordinary and on Zivo. $msg'
                : msg,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          backgroundColor: AppColors.errorColor,
        ),
      );
      if (blocked) await _load(initial: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.taskTitle?.trim().isNotEmpty == true
        ? widget.taskTitle!
        : 'Job chat';

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.headingSmall),
            Text(
              'In-app only · saved with this job',
              style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surfaceDark,
            child:             Text(
              'In-app only · every message is safety-checked (Singlish-aware) and kept as evidence for Trust Arbitrator. Phone numbers / off-app apps are redacted.',
              style: AppTextStyles.bodySmall.copyWith(fontSize: 12, height: 1.35),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!.replaceFirst('Exception: ', ''),
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium,
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
                            mine: m['sender_id']?.toString() == _myId,
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Caption from voice (deaf / hard-of-hearing)',
                    onPressed: (_sending || _readOnly)
                        ? null
                        : () async {
                            final caption = await captureA11yCaption(context);
                            if (!mounted || caption == null || caption.isEmpty) {
                              return;
                            }
                            setState(() {
                              _input.text = 'Caption: $caption';
                            });
                            await _send();
                          },
                    icon: const Icon(Icons.closed_caption_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !_readOnly,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: _readOnly
                            ? 'Chat closed for this job'
                            : 'Message the other party…',
                        isDense: true,
                      ),
                    ),
                  ),
                  const Gap(8),
                  IconButton.filled(
                    onPressed: (_sending || _readOnly) ? null : _send,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.accent,
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

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});
  final Map<String, dynamic> message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final role = message['sender_role']?.toString() ?? '';
    final body = message['body']?.toString() ?? '';
    final at = message['created_at']?.toString();
    String time = '';
    if (at != null) {
      final dt = DateTime.tryParse(at)?.toLocal();
      if (dt != null) {
        time =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }

    if (role == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(fontSize: 11, height: 1.35),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? AppColors.accent : AppColors.cardDark,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 4),
            bottomRight: Radius.circular(mine ? 4 : 14),
          ),
          border: mine ? null : Border.all(color: AppColors.borderColor),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              body,
              style: AppTextStyles.bodyMedium.copyWith(
                color: mine ? Colors.white : AppColors.textPrimary,
                height: 1.35,
              ),
            ),
            if (time.isNotEmpty) ...[
              const Gap(4),
              Text(
                time,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 10,
                  color: mine
                      ? Colors.white.withValues(alpha: 0.7)
                      : AppColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
