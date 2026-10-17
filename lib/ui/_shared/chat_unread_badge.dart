import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';

/// WhatsApp-style red numeric badge (top-right of [child]).
class ChatUnreadBadge extends StatelessWidget {
  const ChatUnreadBadge({
    super.key,
    required this.count,
    required this.child,
  });

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    final label = count > 99 ? '99+' : '$count';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -4,
          right: -6,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: const BoxDecoration(
              color: Color(0xFFE53935),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Polls unread for a task chat and wraps [builder] with the count.
class ChatUnreadPoller extends StatefulWidget {
  const ChatUnreadPoller({
    super.key,
    required this.taskId,
    required this.builder,
    this.interval = const Duration(seconds: 4),
  });

  final String taskId;
  final Widget Function(BuildContext context, int unread) builder;
  final Duration interval;

  @override
  State<ChatUnreadPoller> createState() => _ChatUnreadPollerState();
}

class _ChatUnreadPollerState extends State<ChatUnreadPoller> {
  Timer? _timer;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(widget.interval, (_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant ChatUnreadPoller oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId) {
      _unread = 0;
      _refresh();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final n =
          await context.read<TaskRepository>().getTaskChatUnread(widget.taskId);
      if (!mounted) return;
      if (n != _unread) setState(() => _unread = n);
    } catch (_) {
      /* guest / closed chat */
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _unread);
}
