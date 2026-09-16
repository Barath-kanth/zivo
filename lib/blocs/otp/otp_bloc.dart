import 'dart:async';
import 'package:hyperlocal/core/services/gcp/subscription_handle.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/models/task_status.dart';
import 'package:hyperlocal/blocs/task/task_bloc.dart';

// ── Events ──────────────────────────────────────────────────────────────────
abstract class OtpEvent extends Equatable {
  const OtpEvent();
  @override
  List<Object?> get props => [];
}

class OtpSubscribeToTask extends OtpEvent {
  const OtpSubscribeToTask(this.taskId);
  final String taskId;
  @override
  List<Object?> get props => [taskId];
}

class OtpUnsubscribeFromTask extends OtpEvent {}

class OtpVerifyStart extends OtpEvent {
  const OtpVerifyStart({required this.taskId, required this.enteredOtp});
  final String taskId;
  final String enteredOtp;
  @override
  List<Object?> get props => [taskId, enteredOtp];
}

class OtpVerifyEnd extends OtpEvent {
  const OtpVerifyEnd({required this.taskId, required this.enteredOtp});
  final String taskId;
  final String enteredOtp;
  @override
  List<Object?> get props => [taskId, enteredOtp];
}

class OtpTaskRealtimeUpdated extends OtpEvent {
  const OtpTaskRealtimeUpdated(this.task);
  final Task task;
  @override
  List<Object?> get props => [task];
}

// ── States ──────────────────────────────────────────────────────────────────
abstract class OtpState extends Equatable {
  const OtpState();
  @override
  List<Object?> get props => [];
}

class OtpInitial extends OtpState {}
class OtpVerifying extends OtpState {}

class OtpStateOpen extends OtpState {
  const OtpStateOpen(this.task);
  final Task task;
  @override
  List<Object?> get props => [task];
}

class OtpStateMatched extends OtpState {
  const OtpStateMatched({required this.task, this.errorMessage});
  final Task task;
  final String? errorMessage;
  @override
  List<Object?> get props => [task, errorMessage];
}

class OtpStateInProgress extends OtpState {
  const OtpStateInProgress({required this.task, this.errorMessage});
  final Task task;
  final String? errorMessage;
  @override
  List<Object?> get props => [task, errorMessage];
}

class OtpStateCompleted extends OtpState {
  const OtpStateCompleted(this.task);
  final Task task;
  @override
  List<Object?> get props => [task];
}

class OtpFailure extends OtpState {
  const OtpFailure(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

// ── BLoC ────────────────────────────────────────────────────────────────────

/// Manages the OTP guard state machine:
/// matched → (start OTP verified) → in_progress → (end OTP verified) → completed
///
/// Falls back to the TaskBloc's in-memory demo data when Supabase is unavailable.
class OtpBloc extends Bloc<OtpEvent, OtpState> {
  OtpBloc({
    required TaskRepository taskRepository,
    required TaskBloc taskBloc,
  })  : _taskRepository = taskRepository,
        _taskBloc = taskBloc,
        super(OtpInitial()) {
    on<OtpSubscribeToTask>(_onSubscribe);
    on<OtpUnsubscribeFromTask>(_onUnsubscribe);
    on<OtpVerifyStart>(_onVerifyStart);
    on<OtpVerifyEnd>(_onVerifyEnd);
    on<OtpTaskRealtimeUpdated>(_onRealtimeUpdated);
  }

  final TaskRepository _taskRepository;
  final TaskBloc _taskBloc;
  SubscriptionHandle? _channel;

  static bool isDemoTask(Task task) {
    final id = task.id;
    final clientId = task.clientId;
    final helperId = task.helperId ?? '';
    return id.startsWith('demo-') ||
        id.startsWith('task-demo-') ||
        clientId.startsWith('demo-') ||
        clientId.startsWith('client-demo-') ||
        helperId.startsWith('demo-') ||
        helperId.startsWith('helper-demo-');
  }

  /// Try Supabase first, then fall back to the in-memory TaskBloc demo list.
  Future<Task?> _resolveTask(String taskId) async {
    if (taskId == 'none' || taskId.isEmpty) return null;

    // 1. In-memory first for demo IDs (avoid stale/null remote)
    final local = _taskBloc.findTaskById(taskId);
    if (local != null && isDemoTask(local)) return local;

    // 2. Try remote
    final remote = await _taskRepository.getTaskById(taskId);
    if (remote != null) return remote;

    // 3. Helper's accepted/active job cache
    final active = _taskBloc.getActiveTaskForHelper();
    if (active != null && active.id == taskId) return active;

    return local;
  }

  Future<void> _onSubscribe(
    OtpSubscribeToTask event,
    Emitter<OtpState> emit,
  ) async {
    final task = await _resolveTask(event.taskId);
    if (task == null) {
      emit(const OtpFailure('Task not found'));
      return;
    }

    _emitForTask(task, emit);

    // Subscribe to realtime updates (silently skips if no connection)
    try {
      _channel = _taskRepository.subscribeToTask(
        taskId: event.taskId,
        onUpdate: (data) => add(OtpTaskRealtimeUpdated(Task.fromJson(data))),
      );
    } catch (_) {
      // In demo mode realtime won't connect — that's fine.
    }
  }

  Future<void> _onUnsubscribe(
    OtpUnsubscribeFromTask event,
    Emitter<OtpState> emit,
  ) async {
    if (_channel != null) {
      _taskRepository.unsubscribe(_channel!);
      _channel = null;
    }
    emit(OtpInitial());
  }

  Future<void> _onVerifyStart(
    OtpVerifyStart event,
    Emitter<OtpState> emit,
  ) async {
    final currentTask = _getCurrentTask();
    if (currentTask == null) return;

    emit(OtpVerifying());

    // Demo-only short-circuit (never for live Supabase task IDs)
    if (isDemoTask(currentTask) && currentTask.startOtp != null) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (event.enteredOtp == currentTask.startOtp) {
        final inProgress = currentTask.copyWith(status: TaskStatus.inProgress);
        _taskBloc.syncDemoTaskStatus(inProgress);
        emit(OtpStateInProgress(task: inProgress));
      } else {
        emit(OtpStateMatched(
          task: currentTask,
          errorMessage: 'Wrong OTP — try ${currentTask.startOtp}',
        ));
      }
      return;
    }

    // Live mode: verify via Supabase (always — even when start_otp is present)
    try {
      final updatedTask = await _taskRepository.verifyStartOtp(
        taskId: event.taskId,
        enteredOtp: event.enteredOtp,
      );
      emit(OtpStateInProgress(task: updatedTask));
    } on Exception catch (e) {
      emit(OtpStateMatched(
        task: currentTask,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      ));
    }
  }

  Future<void> _onVerifyEnd(
    OtpVerifyEnd event,
    Emitter<OtpState> emit,
  ) async {
    final currentTask = _getCurrentTask();
    if (currentTask == null) return;

    emit(OtpVerifying());

    if (isDemoTask(currentTask) && currentTask.endOtp != null) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (event.enteredOtp == currentTask.endOtp) {
        final completed = currentTask.copyWith(
          status: TaskStatus.completed,
          completedAt: DateTime.now(),
        );
        _taskBloc.syncDemoTaskStatus(completed);
        emit(OtpStateCompleted(completed));
      } else {
        emit(OtpStateInProgress(
          task: currentTask,
          errorMessage: 'Wrong OTP — try ${currentTask.endOtp}',
        ));
      }
      return;
    }

    try {
      final updatedTask = await _taskRepository.verifyEndOtp(
        taskId: event.taskId,
        enteredOtp: event.enteredOtp,
      );
      emit(OtpStateCompleted(updatedTask));
    } on Exception catch (e) {
      emit(OtpStateInProgress(
        task: currentTask,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      ));
    }
  }

  Future<void> _onRealtimeUpdated(
    OtpTaskRealtimeUpdated event,
    Emitter<OtpState> emit,
  ) async {
    _emitForTask(event.task, emit);
  }

  void _emitForTask(Task task, Emitter<OtpState> emit) {
    switch (task.status) {
      case TaskStatus.open:
        emit(OtpStateOpen(task));
        break;
      case TaskStatus.matched:
        emit(OtpStateMatched(task: task));
        break;
      case TaskStatus.inProgress:
        emit(OtpStateInProgress(task: task));
        break;
      case TaskStatus.completed:
        emit(OtpStateCompleted(task));
        break;
      default:
        emit(OtpInitial());
    }
  }

  Task? _getCurrentTask() {
    if (state is OtpStateOpen) return (state as OtpStateOpen).task;
    if (state is OtpStateMatched) return (state as OtpStateMatched).task;
    if (state is OtpStateInProgress) return (state as OtpStateInProgress).task;
    return null;
  }

  @override
  Future<void> close() {
    if (_channel != null) {
      _taskRepository.unsubscribe(_channel!);
    }
    return super.close();
  }
}
