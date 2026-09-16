import 'package:equatable/equatable.dart';
import 'package:hyperlocal/data/models/task.dart';

// ── Events ─────────────────────────────────────────────────────────────────
abstract class TaskEvent extends Equatable {
  const TaskEvent();
  @override
  List<Object?> get props => [];
}

class TaskFetchClientTasks extends TaskEvent {
  const TaskFetchClientTasks(this.clientId);
  final String clientId;
  @override
  List<Object?> get props => [clientId];
}

class TaskFetchNearbyTasks extends TaskEvent {}

class TaskCreate extends TaskEvent {
  const TaskCreate(this.task);
  final Task task;
  @override
  List<Object?> get props => [task];
}

class TaskAccept extends TaskEvent {
  const TaskAccept({required this.taskId, required this.helperId});
  final String taskId;
  final String helperId;
  @override
  List<Object?> get props => [taskId, helperId];
}

class TaskCancel extends TaskEvent {
  const TaskCancel(this.taskId);
  final String taskId;
  @override
  List<Object?> get props => [taskId];
}

class TaskRealtimeUpdated extends TaskEvent {
  const TaskRealtimeUpdated(this.task);
  final Task task;
  @override
  List<Object?> get props => [task];
}

class TaskRealtimeInserted extends TaskEvent {
  const TaskRealtimeInserted(this.task);
  final Task task;
  @override
  List<Object?> get props => [task];
}

class TaskRealtimeRemoved extends TaskEvent {
  const TaskRealtimeRemoved(this.taskId);
  final String taskId;
  @override
  List<Object?> get props => [taskId];
}

class TaskSubscribeToFeed extends TaskEvent {}
class TaskUnsubscribeFromFeed extends TaskEvent {}

// ── States ─────────────────────────────────────────────────────────────────
abstract class TaskState extends Equatable {
  const TaskState();
  @override
  List<Object?> get props => [];
}

class TaskInitial extends TaskState {}
class TaskLoading extends TaskState {}

class TaskClientLoaded extends TaskState {
  const TaskClientLoaded(this.tasks);
  final List<Task> tasks;
  @override
  List<Object?> get props => [tasks];
}

class TaskNearbyLoaded extends TaskState {
  const TaskNearbyLoaded(this.tasks);
  final List<Task> tasks;
  @override
  List<Object?> get props => [tasks];
}

class TaskCreated extends TaskState {
  const TaskCreated(this.task);
  final Task task;
  @override
  List<Object?> get props => [task];
}

class TaskAccepted extends TaskState {
  const TaskAccepted(this.task);
  final Task task;
  @override
  List<Object?> get props => [task];
}

class TaskFailure extends TaskState {
  const TaskFailure(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
