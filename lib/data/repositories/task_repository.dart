import 'dart:async';

import 'package:hyperlocal/core/services/gcp/gcp_api_client.dart';
import 'package:hyperlocal/core/services/gcp/subscription_handle.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/models/task_status.dart';
import 'location_repository.dart';

class TaskRepository {
  TaskRepository(this._api, this._location);

  final GcpApiClient _api;
  final LocationRepository _location;

  Future<Map<String, dynamic>> safetyCheck({
    required String title,
    required String description,
  }) {
    return _api.postJson(
      '/tasks/safety-check',
      {'title': title, 'description': description, 'languageHint': 'mixed'},
      auth: false,
    );
  }

  Future<Map<String, dynamic>> matchHelpers(String taskId) {
    return _api.postJson('/tasks/$taskId/match', {});
  }

  Future<Map<String, dynamic>> reconcileReceipt({
    required String taskId,
    required String shoppingList,
    List<int>? imageBytes,
  }) {
    return _api.postMultipart(
      '/tasks/$taskId/receipt',
      fields: {'shoppingList': shoppingList},
      fileBytes: imageBytes,
    );
  }

  Future<Task> createTask(Task task) async {
    if (task.clientId.startsWith('demo-')) {
      return task.copyWith(
        goodsBudget: task.goodsBudget,
        requiresPurchaseProof: task.goodsBudget > 0 || task.isPurchaseTask,
      );
    }

    final loc = task.location;
    final payload = <String, dynamic>{
      'title': task.title,
      'description': task.description,
      'category': task.category.name,
      'estimated_hours': task.estimatedHours,
      'hourly_rate': task.hourlyRate,
      'goods_budget': task.goodsBudget,
      'lat': loc.latitude,
      'lon': loc.longitude,
    };
    final address = task.locationAddress ?? task.locationLabel;
    if (address != null && address.trim().isNotEmpty) {
      payload['location_address'] = address.trim();
    }
    if (task.locationLabel != null && task.locationLabel!.trim().isNotEmpty) {
      payload['location_label'] = task.locationLabel!.trim();
    }
    if (task.photoUrls.isNotEmpty) {
      payload['photo_urls'] = task.photoUrls;
    }

    final data = await _api.postJson('/tasks', payload);

    final created = Task.fromJson(Map<String, dynamic>.from(data['task'] as Map));
    return created.copyWith(
      goodsBudget: task.goodsBudget,
      requiresPurchaseProof: task.goodsBudget > 0 || task.isPurchaseTask,
      photoUrls: task.photoUrls.isNotEmpty ? task.photoUrls : created.photoUrls,
    );
  }

  Future<String> uploadTaskPhoto({
    required List<int> bytes,
    String filename = 'photo.jpg',
  }) {
    return _api.uploadTaskPhoto(bytes: bytes, filename: filename);
  }

  Future<List<Task>> getClientTasks(String clientId) async {
    final data = await _api.getJson('/tasks/mine');
    final list = data['tasks'] as List? ?? [];
    return list
        .map((e) => Task.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Task?> getTaskById(String taskId) async {
    try {
      final data = await _api.getJson('/tasks/$taskId');
      return Task.fromJson(Map<String, dynamic>.from(data['task'] as Map));
    } catch (_) {
      return null;
    }
  }

  Future<List<Task>> getNearbyOpenTasks() async {
    final position = await _location.fetchCurrentPosition();
    final lat = position?.latitude ?? 6.9271;
    final lng = position?.longitude ?? 79.8612;
    final data = await _api.getJson('/tasks/open', query: {
      'lat': '$lat',
      'lng': '$lng',
    });
    final list = data['tasks'] as List? ?? [];
    return list
        .map((e) => Task.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Task> acceptTask({
    required String taskId,
    required String helperId,
  }) async {
    final data = await _api.postJson('/tasks/$taskId/accept', {});
    return Task.fromJson(Map<String, dynamic>.from(data['task'] as Map));
  }

  Future<Task> verifyStartOtp({
    required String taskId,
    required String enteredOtp,
  }) async {
    final task = await getTaskById(taskId);
    if (task == null) throw Exception('Task not found');
    if (task.startOtp != null && task.startOtp != enteredOtp) {
      throw Exception('Invalid Start OTP. Please check with the client.');
    }
    // Local status bump for Cup demo (API can expand later)
    return task.copyWith(status: TaskStatus.inProgress);
  }

  Future<Task> verifyEndOtp({
    required String taskId,
    required String enteredOtp,
  }) async {
    final data = await _api.postJson('/tasks/$taskId/complete', {
      'confirm_code': enteredOtp,
      'receipt_total_lkr': 0,
    });
    return Task.fromJson(Map<String, dynamic>.from(data['task'] as Map));
  }

  Future<Task> cancelTask(String taskId) async {
    final task = await getTaskById(taskId);
    if (task == null) throw Exception('Task not found');
    return task.copyWith(status: TaskStatus.cancelled);
  }

  Future<void> saveShoppingList({
    required String taskId,
    required List<Map<String, dynamic>> items,
  }) async {
    // Persisted in task description on create for Cup; no-op store.
  }

  Future<List<Map<String, dynamic>>> getShoppingList(String taskId) async {
    return [];
  }

  Future<Map<String, dynamic>> submitPurchaseProof({
    required String taskId,
    required String receiptImageUrl,
    required List<String> goodsImageUrls,
    required double receiptTotal,
    String? storeName,
    String? notes,
  }) async {
    final result = await reconcileReceipt(
      taskId: taskId,
      shoppingList: notes ?? '',
    );
    return {
      ...result,
      'receipt_total': receiptTotal,
      'receipt_image_url': receiptImageUrl,
      'goods_image_urls': goodsImageUrls,
      'store_name': storeName,
      'proof_submitted_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<Task> confirmDelivery(String taskId) async {
    final task = await getTaskById(taskId);
    if (task == null) throw Exception('Task not found');
    return task;
  }

  Future<Task> openDispute({
    required String taskId,
    required String reason,
  }) async {
    final task = await getTaskById(taskId);
    if (task == null) throw Exception('Task not found');
    return task.copyWith(status: TaskStatus.disputed, disputeReason: reason);
  }

  SubscriptionHandle subscribeToOpenTasks({
    required void Function(Map<String, dynamic>) onInsert,
    required void Function(Map<String, dynamic>) onUpdate,
    required void Function(Map<String, dynamic>) onDelete,
  }) {
    final timer = Timer.periodic(const Duration(seconds: 8), (_) async {
      try {
        final tasks = await getNearbyOpenTasks();
        for (final t in tasks) {
          onUpdate(t.toJson());
        }
      } catch (_) {}
    });
    return SubscriptionHandle(timer.cancel);
  }

  SubscriptionHandle subscribeToTask({
    required String taskId,
    required void Function(Map<String, dynamic>) onUpdate,
  }) {
    final timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final t = await getTaskById(taskId);
        if (t != null) {
          onUpdate({
            'id': t.id,
            'status': t.status.dbValue,
            'start_otp': t.startOtp,
            'end_otp': t.endOtp,
          });
        }
      } catch (_) {}
    });
    return SubscriptionHandle(timer.cancel);
  }

  void unsubscribe(SubscriptionHandle channel) {
    channel.cancel();
  }
}
