import 'dart:async';
import 'package:hyperlocal/core/services/gcp/subscription_handle.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:hyperlocal/data/models/task_status.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'task_event.dart';

export 'task_event.dart';

class TaskBloc extends Bloc<TaskEvent, TaskState> {
  TaskBloc({required TaskRepository taskRepository})
      : _taskRepository = taskRepository,
        super(TaskInitial()) {
    on<TaskFetchClientTasks>(_onFetchClientTasks);
    on<TaskFetchNearbyTasks>(_onFetchNearbyTasks);
    on<TaskFetchHelperActive>(_onFetchHelperActive);
    on<TaskCreate>(_onCreateTask);
    on<TaskAccept>(_onAcceptTask);
    on<TaskCancel>(_onCancelTask);
    on<TaskRealtimeUpdated>(_onRealtimeUpdated);
    on<TaskRealtimeInserted>(_onRealtimeInserted);
    on<TaskRealtimeRemoved>(_onRealtimeRemoved);
    on<TaskSubscribeToFeed>(_onSubscribeToFeed);
    on<TaskUnsubscribeFromFeed>(_onUnsubscribeFromFeed);
  }

  final TaskRepository _taskRepository;
  SubscriptionHandle? _feedChannel;

  /// Last job this helper accepted (for Active tab / OTP).
  Task? _helperActiveTask;

  List<Task> _openNearbyOnly([List<Task>? source]) {
    final list = source ?? List<Task>.from(_localNearbyTasks);
    return list.where((t) => t.status == TaskStatus.open).toList();
  }

  // ── Client Tasks ────────────────────────────────────────────────────────

  Future<void> _onFetchClientTasks(
    TaskFetchClientTasks event,
    Emitter<TaskState> emit,
  ) async {
    if (!event.silent) emit(TaskLoading());
    try {
      final tasks = await _taskRepository.getClientTasks(event.clientId);
      _localClientTasks
        ..clear()
        ..addAll(tasks);
      emit(TaskClientLoaded(tasks));
    } catch (e) {
      if (!event.silent) emit(TaskFailure(e.toString()));
    }
  }

  // ── Helper Dispatch Feed ─────────────────────────────────────────────────

  Future<void> _onFetchNearbyTasks(
    TaskFetchNearbyTasks event,
    Emitter<TaskState> emit,
  ) async {
    // Only show full-screen loader on first load — not on feed polls.
    final firstLoad = state is! TaskNearbyLoaded;
    if (firstLoad) emit(TaskLoading());
    try {
      final tasks = await _taskRepository.getNearbyOpenTasks();
      _localNearbyTasks
        ..clear()
        ..addAll(tasks);
      emit(TaskNearbyLoaded(tasks));
    } catch (e) {
      if (firstLoad) emit(TaskNearbyLoaded(const []));
    }
  }

  Future<void> _onFetchHelperActive(
    TaskFetchHelperActive event,
    Emitter<TaskState> emit,
  ) async {
    try {
      final tasks = await _taskRepository.getHelperActiveTasks();
      if (tasks.isNotEmpty) {
        _helperActiveTask = tasks.first;
      }
    } catch (_) {}
  }

  Future<void> _onSubscribeToFeed(
    TaskSubscribeToFeed event,
    Emitter<TaskState> emit,
  ) async {
    _feedChannel = _taskRepository.subscribeToOpenTasks(
      onInsert: (data) {
        try {
          add(TaskRealtimeInserted(Task.fromJson(data)));
        } catch (_) {}
      },
      onUpdate: (data) {
        try {
          add(TaskRealtimeUpdated(Task.fromJson(data)));
        } catch (_) {}
      },
      onDelete: (data) => add(TaskRealtimeRemoved(data['id'] as String)),
    );
  }

  Future<void> _onUnsubscribeFromFeed(
    TaskUnsubscribeFromFeed event,
    Emitter<TaskState> emit,
  ) async {
    _feedChannel.let((ch) => _taskRepository.unsubscribe(ch));
    _feedChannel = null;
  }

  // ── Realtime handlers ─────────────────────────────────────────────────────

  Future<void> _onRealtimeUpdated(
    TaskRealtimeUpdated event,
    Emitter<TaskState> emit,
  ) async {
    if (event.task.status.isTerminal) {
      if (_helperActiveTask?.id == event.task.id) {
        _helperActiveTask = null;
      }
    } else if (event.task.status == TaskStatus.matched ||
        event.task.status == TaskStatus.inProgress) {
      _helperActiveTask = event.task;
    }

    final s = state;
    if (s is TaskNearbyLoaded) {
      // Keep nearby feed as open jobs only
      final updated = s.tasks
          .map((t) => t.id == event.task.id ? event.task : t)
          .where((t) => t.status == TaskStatus.open)
          .toList();
      emit(TaskNearbyLoaded(
        event.task.status == TaskStatus.open
            ? updated
            : updated.where((t) => t.id != event.task.id).toList(),
      ));
    } else if (s is TaskClientLoaded) {
      final updated = s.tasks
          .map((t) => t.id == event.task.id ? event.task : t)
          .where((t) =>
              !t.status.isTerminal || t.status == TaskStatus.completed)
          .toList();
      if (!updated.any((t) => t.id == event.task.id) &&
          event.task.status == TaskStatus.completed) {
        updated.insert(0, event.task);
      }
      emit(TaskClientLoaded(updated));
    } else if (s is TaskAccepted) {
      // Restore open feed after accept so Jobs tab is not blank
      emit(TaskNearbyLoaded(_openNearbyOnly()));
    } else {
      // Force listeners (client home) to rebuild after demo OTP complete
      emit(TaskNearbyLoaded(_openNearbyOnly()));
    }
  }

  Future<void> _onRealtimeInserted(
    TaskRealtimeInserted event,
    Emitter<TaskState> emit,
  ) async {
    if (state is TaskNearbyLoaded) {
      emit(TaskNearbyLoaded([event.task, ...(state as TaskNearbyLoaded).tasks]));
    }
  }

  Future<void> _onRealtimeRemoved(
    TaskRealtimeRemoved event,
    Emitter<TaskState> emit,
  ) async {
    if (state is TaskNearbyLoaded) {
      emit(TaskNearbyLoaded(
        (state as TaskNearbyLoaded).tasks.where((t) => t.id != event.taskId).toList(),
      ));
    }
  }

  // ── Task Creation ────────────────────────────────────────────────────────

  Future<void> _onCreateTask(
    TaskCreate event,
    Emitter<TaskState> emit,
  ) async {
    emit(TaskLoading());
    if (event.task.clientId.startsWith('demo-')) {
      final createdTask = Task(
        id: 'task-demo-${DateTime.now().millisecondsSinceEpoch}',
        clientId: event.task.clientId,
        title: event.task.title,
        description: event.task.description,
        category: event.task.category,
        estimatedHours: event.task.estimatedHours,
        hourlyRate: event.task.hourlyRate,
        totalAmount: event.task.totalAmount,
        location: event.task.location,
        locationAddress: event.task.locationAddress,
        locationLabel: event.task.locationLabel,
        status: TaskStatus.open,
        startOtp: '1234',
        endOtp: '5678',
        createdAt: DateTime.now(),
        goodsBudget: event.task.goodsBudget,
        requiresPurchaseProof: event.task.requiresPurchaseProof,
      );
      _localClientTasks.insert(0, createdTask);
      _localNearbyTasks.insert(0, createdTask);
      emit(TaskCreated(createdTask));
      return;
    }
    try {
      final createdTask = await _taskRepository.createTask(event.task);
      _localNearbyTasks.insert(0, createdTask);
      emit(TaskCreated(createdTask));
      // Keep helper Jobs feed in sync when the same device switches modes.
      emit(TaskNearbyLoaded(_openNearbyOnly([createdTask, ..._localNearbyTasks])));
    } catch (e) {
      emit(TaskFailure(e.toString()));
    }
  }

  // ── Task Accept ───────────────────────────────────────────────────────────

  Future<void> _onAcceptTask(
    TaskAccept event,
    Emitter<TaskState> emit,
  ) async {
    emit(TaskLoading());
    if (event.taskId.startsWith('task-demo-')) {
      Task? task;
      for (int i = 0; i < _localNearbyTasks.length; i++) {
        if (_localNearbyTasks[i].id == event.taskId) {
          _localNearbyTasks[i] = _localNearbyTasks[i].copyWith(
            status: TaskStatus.matched,
            helperId: event.helperId,
            matchedAt: DateTime.now(),
            startOtp: '1234',
            endOtp: '5678',
          );
          task = _localNearbyTasks[i];
        }
      }
      for (int i = 0; i < _localClientTasks.length; i++) {
        if (_localClientTasks[i].id == event.taskId) {
          _localClientTasks[i] = _localClientTasks[i].copyWith(
            status: TaskStatus.matched,
            helperId: event.helperId,
            matchedAt: DateTime.now(),
            startOtp: '1234',
            endOtp: '5678',
          );
          task ??= _localClientTasks[i];
        }
      }
      if (task != null) {
        _helperActiveTask = task;
        emit(TaskAccepted(task));
        // Restore Jobs feed (open only) so it does not stay blank
        emit(TaskNearbyLoaded(_openNearbyOnly()));
      } else {
        emit(const TaskFailure('Demo task not found in memory'));
      }
      return;
    }
    try {
      final task = await _taskRepository.acceptTask(
        taskId: event.taskId,
        helperId: event.helperId,
      );
      _helperActiveTask = task;
      emit(TaskAccepted(task));
      // Refresh open nearby feed (keep _helperActiveTask — Active tab uses it)
      try {
        final nearby = await _taskRepository.getNearbyOpenTasks();
        _localNearbyTasks
          ..clear()
          ..addAll(nearby);
        emit(TaskNearbyLoaded(_openNearbyOnly(nearby)));
      } catch (_) {
        emit(TaskNearbyLoaded(const []));
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      emit(TaskFailure(msg));
      // Restore Jobs feed so Accept failure does not blank the list
      try {
        final nearby = await _taskRepository.getNearbyOpenTasks();
        emit(TaskNearbyLoaded(_openNearbyOnly(nearby)));
      } catch (_) {}
    }
  }

  // ── Task Cancel ───────────────────────────────────────────────────────────

  Future<void> _onCancelTask(
    TaskCancel event,
    Emitter<TaskState> emit,
  ) async {
    try {
      final cancelled = await _taskRepository.cancelTask(event.taskId);
      add(TaskRealtimeUpdated(cancelled));
    } catch (e) {
      emit(TaskFailure(e.toString()));
    }
  }

  List<Task> peekClientTasks() => List<Task>.unmodifiable(_localClientTasks);

  /// Persist demo OTP / status changes back into memory lists and notify UI.
  void syncDemoTaskStatus(Task updated) => syncTaskStatus(updated);

  /// Keep client Active Requests + helper Active in sync after Start/End OTP.
  void syncTaskStatus(Task updated) {
    for (int i = 0; i < _localClientTasks.length; i++) {
      if (_localClientTasks[i].id == updated.id) {
        _localClientTasks[i] = updated;
      }
    }
    for (int i = 0; i < _localNearbyTasks.length; i++) {
      if (_localNearbyTasks[i].id == updated.id) {
        _localNearbyTasks[i] = updated;
      }
    }
    if (updated.status.isTerminal) {
      if (_helperActiveTask?.id == updated.id) {
        _helperActiveTask = null;
      }
    } else {
      final active = _helperActiveTask;
      if (active != null && active.id == updated.id) {
        _helperActiveTask = updated;
      }
    }
    add(TaskRealtimeUpdated(updated));
  }

  /// Look up a task across all in-memory demo lists + helper active cache.
  Task? findTaskById(String taskId) {
    if (taskId.isEmpty || taskId == 'none') return null;
    final active = _helperActiveTask;
    if (active != null && active.id == taskId) return active;
    for (final t in _localClientTasks) {
      if (t.id == taskId) return t;
    }
    for (final t in _localNearbyTasks) {
      if (t.id == taskId) return t;
    }
    final s = state;
    if (s is TaskAccepted && s.task.id == taskId) return s.task;
    if (s is TaskClientLoaded) {
      try {
        return s.tasks.firstWhere((t) => t.id == taskId);
      } catch (_) {}
    }
    if (s is TaskNearbyLoaded) {
      try {
        return s.tasks.firstWhere((t) => t.id == taskId);
      } catch (_) {}
    }
    return null;
  }

  /// Active job for the current helper — never pick a seeded client match
  /// that was never accepted by this helper.
  Task? getActiveTaskForHelper({String? helperId}) {
    final active = _helperActiveTask;
    if (active != null &&
        (active.status == TaskStatus.matched ||
            active.status == TaskStatus.inProgress) &&
        (helperId == null ||
            helperId.isEmpty ||
            active.helperId == null ||
            active.helperId == helperId)) {
      return active;
    }

    bool isActiveForHelper(Task t) {
      if (t.status != TaskStatus.matched &&
          t.status != TaskStatus.inProgress) {
        return false;
      }
      if (helperId == null || helperId.isEmpty) return true;
      return t.helperId == helperId;
    }

    try {
      return _localNearbyTasks.firstWhere(isActiveForHelper);
    } catch (_) {}
    try {
      return _localClientTasks.firstWhere(isActiveForHelper);
    } catch (_) {}

    final s = state;
    if (s is TaskAccepted &&
        (s.task.status == TaskStatus.matched ||
            s.task.status == TaskStatus.inProgress) &&
        (helperId == null ||
            helperId.isEmpty ||
            s.task.helperId == helperId)) {
      return s.task;
    }
    if (s is TaskNearbyLoaded) {
      try {
        return s.tasks.firstWhere(isActiveForHelper);
      } catch (_) {}
    }
    return null;
  }

  /// Memory first, then Cloud Run — used by Active tab after refresh.
  Future<Task?> resolveHelperActiveTask({String? helperId}) async {
    final local = getActiveTaskForHelper(helperId: helperId);
    if (local != null) return local;
    try {
      final tasks = await _taskRepository.getHelperActiveTasks();
      if (tasks.isEmpty) return null;
      _helperActiveTask = tasks.first;
      return _helperActiveTask;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() {
    _feedChannel.let((ch) => _taskRepository.unsubscribe(ch));
    return super.close();
  }
}

// Local in-memory lists for legacy demo-id mutation paths (start empty).
final List<Task> _localClientTasks = [];
final List<Task> _localNearbyTasks = [];

extension _Let<T> on T? {
  void let(void Function(T) fn) {
    if (this != null) fn(this as T);
  }
}
