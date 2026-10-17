import 'dart:async';
import 'dart:convert';

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

  /// Fair floor quote (boost only; never undercut helper).
  Future<Map<String, dynamic>> priceQuote({
    required String title,
    required String description,
    required double lat,
    required double lon,
    String category = 'errandRun',
    int? durationMinutes,
    String urgency = 'urgent',
    double? destLat,
    double? destLon,
    double? travelKm,
    int clientBoostLkr = 0,
    String? deadlineAt,
    Map<String, dynamic>? contextFields,
  }) {
    return _api.postJson(
      '/tasks/price-quote',
      {
        'title': title,
        'description': description,
        'category': category,
        'lat': lat,
        'lon': lon,
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
        'urgency': urgency,
        if (destLat != null) 'dest_lat': destLat,
        if (destLon != null) 'dest_lon': destLon,
        if (travelKm != null) 'travel_km': travelKm,
        if (clientBoostLkr > 0) 'client_boost_lkr': clientBoostLkr,
        if (deadlineAt != null) 'deadline_at': deadlineAt,
        if (contextFields != null && contextFields.isNotEmpty)
          'context_fields': contextFields,
      },
      auth: false,
    );
  }

  /// Context-specific pricing questions for this task.
  Future<Map<String, dynamic>> pricingFields({
    required String title,
    required String description,
    required String category,
  }) {
    return _api.postJson(
      '/tasks/pricing-fields',
      {
        'title': title,
        'description': description,
        'category': category,
      },
      auth: false,
    );
  }

  /// Pillar 1 — Instant Dispatch (Available helpers within walk radius).
  Future<Map<String, dynamic>> instantDispatch({
    required String title,
    required String description,
    required double lat,
    required double lon,
    String category = 'errandRun',
    int durationMinutes = 15,
    String urgency = 'urgent',
    double? destLat,
    double? destLon,
    double? travelKm,
    int clientBoostLkr = 0,
  }) {
    return _api.postJson('/tasks/dispatch', {
      'title': title,
      'description': description,
      'category': category,
      'lat': lat,
      'lon': lon,
      'duration_minutes': durationMinutes,
      'urgency': urgency,
      if (destLat != null) 'dest_lat': destLat,
      if (destLon != null) 'dest_lon': destLon,
      if (travelKm != null) 'travel_km': travelKm,
      if (clientBoostLkr > 0) 'client_boost_lkr': clientBoostLkr,
    });
  }

  /// Pillar 3 — Open street batches neighbors can piggyback onto.
  Future<Map<String, dynamic>> listStreetBatches({
    required double lat,
    required double lon,
  }) {
    return _api.getJson('/batches/nearby', query: {
      'lat': '$lat',
      'lon': '$lon',
    });
  }

  /// Pillar 3 — Join an open street batch at a discounted micro-price.
  Future<Map<String, dynamic>> joinStreetBatch({
    required String batchId,
    required String title,
    required String description,
    required double lat,
    required double lon,
    int durationMinutes = 10,
    String urgency = 'soon',
  }) {
    return _api.postJson('/batches/join', {
      'batch_id': batchId,
      'title': title,
      'description': description,
      'lat': lat,
      'lon': lon,
      'duration_minutes': durationMinutes,
      'urgency': urgency,
    });
  }

  /// Pillar 3 — Helper stacked stops on one street.
  Future<Map<String, dynamic>> helperBatchRoute() {
    return _api.getJson('/me/batch-route');
  }

  /// Pillar 4 — Stake LKR to vouch a neighbor helper.
  Future<Map<String, dynamic>> vouchNeighbor({
    required String helperId,
    String? note,
    double lat = 6.9271,
    double lon = 79.8612,
  }) {
    return _api.postJson('/vouch', {
      'helper_id': helperId,
      if (note != null) 'note': note,
      'lat': lat,
      'lon': lon,
    });
  }

  Future<Map<String, dynamic>> helperTrust(String helperId) {
    return _api.getJson('/helpers/$helperId/trust');
  }

  Future<Map<String, dynamic>> vouchMeta() {
    return _api.getJson('/vouch/meta');
  }

  Future<Map<String, dynamic>> listLiveHelpers({
    required double lat,
    required double lon,
  }) {
    return _api.getJson('/helpers/live', query: {
      'lat': '$lat',
      'lon': '$lon',
    });
  }

  Future<Map<String, dynamic>> setHelperPresence({
    required bool available,
    double? lat,
    double? lon,
  }) {
    return _api.postJson('/me/presence', {
      'available': available,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
    });
  }

  Future<Map<String, dynamic>> matchHelpers(String taskId) {
    return _api.postJson('/tasks/$taskId/match', {});
  }

  /// Client hires a recommended helper from Explain-my-match.
  Future<Task> assignHelper({
    required String taskId,
    required String helperId,
  }) async {
    final data = await _api.postJson('/tasks/$taskId/assign', {
      'helper_id': helperId,
    });
    return Task.fromJson(Map<String, dynamic>.from(data['task'] as Map));
  }

  Future<Map<String, dynamic>> reconcileReceipt({
    required String taskId,
    required String shoppingList,
    List<int>? imageBytes,
    double? budgetLkr,
  }) {
    return _api.postMultipart(
      '/tasks/$taskId/receipt',
      fields: {
        'shoppingList': shoppingList,
        if (budgetLkr != null) 'budget_lkr': budgetLkr.toStringAsFixed(0),
      },
      fileBytes: imageBytes,
    );
  }

  Future<Task> createTask(
    Task task, {
    String? deadlineAt,
    int clientBoostLkr = 0,
    double? travelKm,
    String urgency = 'normal',
    Map<String, dynamic>? contextFields,
  }) async {
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
      'goods_budget': task.goodsBudget,
      'lat': loc.latitude,
      'lon': loc.longitude,
      'deadline_at': deadlineAt ??
          DateTime.now().add(const Duration(hours: 24)).toUtc().toIso8601String(),
      'urgency': urgency,
      if (clientBoostLkr > 0) 'client_boost_lkr': clientBoostLkr,
      if (travelKm != null) 'travel_km': travelKm,
      if (contextFields != null && contextFields.isNotEmpty)
        'context_fields': contextFields,
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
    if (task.photoPaths.isNotEmpty) {
      payload['photo_paths'] = task.photoPaths;
    }
    if (task.bookedForUserId != null && task.bookedForUserId!.isNotEmpty) {
      payload['booked_for_user_id'] = task.bookedForUserId;
    }
    if (task.bookedForName != null && task.bookedForName!.trim().isNotEmpty) {
      payload['booked_for_name'] = task.bookedForName!.trim();
    }

    final data = await _api.postJson('/tasks', payload);

    final created = Task.fromJson(Map<String, dynamic>.from(data['task'] as Map));
    return created.copyWith(
      goodsBudget: task.goodsBudget,
      requiresPurchaseProof: task.goodsBudget > 0 || task.isPurchaseTask,
      photoUrls: task.photoUrls.isNotEmpty ? task.photoUrls : created.photoUrls,
      photoPaths: task.photoPaths.isNotEmpty ? task.photoPaths : created.photoPaths,
    );
  }

  Future<Map<String, String>> uploadTaskPhoto({
    required List<int> bytes,
    String filename = 'photo.jpg',
  }) {
    return _api.uploadTaskPhoto(bytes: bytes, filename: filename);
  }

  /// Show it. Get help. — photo → category + draft + confirm questions.
  Future<Map<String, dynamic>> suggestFromPhoto({
    required List<int> imageBytes,
    String filename = 'scene.jpg',
    String? hint,
  }) {
    return _api.postMultipart(
      '/tasks/suggest-from-photo',
      fields: {
        if (hint != null && hint.trim().isNotEmpty) 'hint': hint.trim(),
      },
      fileBytes: imageBytes,
      fileField: 'photo',
      filename: filename,
    );
  }

  /// Speak your task — audio → draft (accessibility: voice instead of typing).
  Future<Map<String, dynamic>> suggestFromVoice({
    List<int>? audioBytes,
    String lang = 'en',
    String filename = 'clip.webm',
    String contentType = 'audio/webm',
  }) {
    return _api.postMultipart(
      '/tasks/suggest-from-voice',
      fields: {'lang': lang},
      fileBytes: audioBytes,
      fileField: 'audio',
      filename: filename,
      contentType: contentType,
    );
  }

  /// Speak → understand → split, one server call (replaces suggestFromVoice + planTaskBundle).
  Future<Map<String, dynamic>> voicePlan({
    required List<int> audioBytes,
    String lang = 'auto',
    String filename = 'clip.webm',
    String contentType = 'audio/webm',
  }) {
    return _api.postMultipart(
      '/tasks/voice-plan',
      fields: {'lang': lang},
      fileBytes: audioBytes,
      fileField: 'audio',
      filename: filename,
      contentType: contentType,
    );
  }

  // ── Ability-aware work ──────────────────────────────────────────────────

  Future<void> saveAbilityProfile({
    required List<String> abilities,
    required bool disclose,
    required String note,
  }) async {
    await _api.patchJson('/me', {
      'abilities': abilities,
      'disclose_access': disclose,
      'access_note': note,
    });
  }

  Future<Map<String, dynamic>> abilityFit(String taskId) =>
      _api.getJson('/tasks/$taskId/ability-fit');

  Future<Map<String, dynamic>> adaptBrief(String taskId, {String lang = 'en'}) =>
      _api.postJson('/tasks/$taskId/adapt-brief', {'lang': lang});

  Future<Task> declineHelper(String taskId, {String? reason}) async {
    final data = await _api.postJson('/tasks/$taskId/decline-helper', {
      if (reason != null) 'reason': reason,
    });
    return Task.fromJson(Map<String, dynamic>.from(data['task'] as Map));
  }

  /// Zivo Eyes: mode = describe | read | match.
  Future<Map<String, dynamic>> zivoEyes({
    required List<int> imageBytes,
    required String mode,
    String lang = 'en',
    List<String> items = const [],
    String? hint,
  }) {
    return _api.postMultipart(
      '/a11y/eyes',
      fields: {
        'mode': mode,
        'lang': lang,
        if (items.isNotEmpty) 'items': jsonEncode(items),
        if (hint != null) 'hint': hint,
      },
      fileBytes: imageBytes,
      fileField: 'image',
      filename: 'eyes.jpg',
    );
  }

  Future<Map<String, dynamic>> doorstepTalk({
    required List<int> audioBytes,
    String lang = 'en',
  }) {
    return _api.postMultipart(
      '/a11y/doorstep',
      fields: {'lang': lang},
      fileBytes: audioBytes,
      fileField: 'audio',
      filename: 'clip.webm',
      contentType: 'audio/webm',
    );
  }

  /// Entrance photo → stairs/ramp/door note (does not attach to a task).
  Future<Map<String, dynamic>> accessAudit({
    required List<int> imageBytes,
    String lang = 'en',
    String? hint,
  }) {
    return _api.postMultipart(
      '/a11y/access-audit',
      fields: {
        'lang': lang,
        if (hint != null) 'hint': hint,
      },
      fileBytes: imageBytes,
      fileField: 'image',
      filename: 'entrance.jpg',
    );
  }

  /// Client: attach an access audit to a posted task so helpers see it.
  Future<Map<String, dynamic>> attachAccessAudit({
    required String taskId,
    required List<int> imageBytes,
    String lang = 'en',
    String? hint,
  }) {
    return _api.postMultipart(
      '/tasks/$taskId/access-audit',
      fields: {
        'lang': lang,
        if (hint != null) 'hint': hint,
      },
      fileBytes: imageBytes,
      fileField: 'image',
      filename: 'entrance.jpg',
    );
  }

  /// One problem → several related task drafts.
  Future<Map<String, dynamic>> planTaskBundle({
    required String problem,
    String? categoryHint,
    String lang = 'auto',
  }) {
    return _api.postJson('/tasks/plan', {
      'problem': problem,
      'lang': lang,
      if (categoryHint != null && categoryHint.isNotEmpty)
        'category_hint': categoryHint,
    });
  }

  /// Checkout selected planned tasks as one escrow bundle.
  Future<Map<String, dynamic>> checkoutTaskBundle({
    required String bundleTitle,
    required double lat,
    required double lon,
    required String deadlineAt,
    required List<Map<String, dynamic>> tasks,
    String? locationLabel,
    String? bookedForUserId,
    String? bookedForName,
  }) {
    return _api.postJson('/tasks/bundle', {
      'bundle_title': bundleTitle,
      'lat': lat,
      'lon': lon,
      'deadline_at': deadlineAt,
      'tasks': tasks,
      if (locationLabel != null) 'location_label': locationLabel,
      if (bookedForUserId != null) 'booked_for_user_id': bookedForUserId,
      if (bookedForName != null) 'booked_for_name': bookedForName,
    });
  }

  Future<Map<String, dynamic>> shareTaskLive(String taskId) {
    return _api.postJson('/tasks/$taskId/share', {});
  }

  Future<Map<String, dynamic>> watchTask(String taskId) {
    return _api.postJson('/tasks/$taskId/watch', {});
  }

  Future<Map<String, dynamic>> getSharedLive(String token) {
    return _api.getJson('/shared/$token', auth: false);
  }

  Future<List<Task>> listWatching() async {
    final data = await _api.getJson('/me/watching');
    final list = data['tasks'] as List? ?? [];
    return list
        .map((e) => Task.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> a11yDescribe({
    List<int>? imageBytes,
    String hint = 'Zivo app screen',
    String lang = 'en',
  }) {
    return _api.postMultipart(
      '/a11y/describe',
      fields: {'hint': hint, 'lang': lang},
      fileBytes: imageBytes,
      fileField: 'image',
      filename: 'scene.jpg',
    );
  }

  Future<Map<String, dynamic>> a11ySimplify(String text, {String lang = 'en'}) {
    return _api.postJson('/a11y/simplify', {'text': text, 'lang': lang});
  }

  Future<Map<String, dynamic>> a11yTranscribe({
    List<int>? audioBytes,
    String lang = 'en',
  }) {
    return _api.postMultipart(
      '/a11y/transcribe',
      fields: {'lang': lang},
      fileBytes: audioBytes,
      fileField: 'audio',
      filename: 'clip.webm',
      contentType: 'audio/webm',
    );
  }

  Future<Map<String, dynamic>> submitCompletionProof({
    required String taskId,
    required List<String> checkedItems,
    List<List<int>> photoBytes = const [],
    String? note,
    double? receiptTotalLkr,
    String? shoppingList,
  }) {
    final extras =
        <({List<int> bytes, String field, String filename, String? contentType})>[];
    for (var i = 0; i < photoBytes.length && i < 3; i++) {
      extras.add((
        bytes: photoBytes[i],
        field: 'photos',
        filename: 'proof_$i.jpg',
        contentType: 'image/jpeg',
      ));
    }
    return _api.postMultipart(
      '/tasks/$taskId/completion-proof',
      fields: {
        'checked_items': jsonEncode(checkedItems),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        if (receiptTotalLkr != null) 'receipt_total_lkr': '$receiptTotalLkr',
        if (shoppingList != null && shoppingList.trim().isNotEmpty)
          'shopping_list': shoppingList.trim(),
      },
      extraFiles: extras,
    );
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

  /// Helper's matched / in-progress jobs for the Active tab.
  Future<List<Task>> getHelperActiveTasks() async {
    final data = await _api.getJson('/tasks/helper/active');
    final list = data['tasks'] as List? ?? [];
    return list
        .map((e) => Task.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Task> verifyStartOtp({
    required String taskId,
    required String enteredOtp,
  }) async {
    final data = await _api.postJson('/tasks/$taskId/start', {
      'start_otp': enteredOtp,
    });
    return Task.fromJson(Map<String, dynamic>.from(data['task'] as Map));
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

  Future<Task> cancelTask(String taskId, {required String reason}) async {
    final res = await _api.postJson('/tasks/$taskId/cancel', {
      'reason': reason,
    });
    final raw = res['task'];
    if (raw is Map) {
      return Task.fromJson(Map<String, dynamic>.from(raw));
    }
    final task = await getTaskById(taskId);
    if (task == null) throw Exception('Task not found');
    return task.copyWith(
      status: TaskStatus.cancelled,
      disputeReason: reason,
    );
  }

  Future<Task> editTask({
    required String taskId,
    String? title,
    String? description,
  }) async {
    final res = await _api.patchJson('/tasks/$taskId', {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
    });
    final raw = res['task'];
    if (raw is Map) {
      return Task.fromJson(Map<String, dynamic>.from(raw));
    }
    throw Exception('Edit failed');
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
    required String shoppingList,
    List<int>? receiptImageBytes,
    double? budgetLkr,
    String? storeName,
    double? receiptTotalHint,
  }) async {
    final photos =
        receiptImageBytes != null ? <List<int>>[receiptImageBytes] : <List<int>>[];
    final result = await submitCompletionProof(
      taskId: taskId,
      checkedItems: const [
        'Till receipt photo',
        'Bag / goods photo',
        'Items match the shopping list',
      ],
      photoBytes: photos,
      note: storeName,
      receiptTotalLkr: receiptTotalHint,
      shoppingList: shoppingList,
    );
    return {
      ...result,
      if (budgetLkr != null) 'budget_lkr': budgetLkr,
      'store_name': storeName,
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
    final res = await _api.postJson('/tasks/$taskId/dispute', {
      'reason': reason,
    });
    final raw = res['task'];
    if (raw is Map) {
      return Task.fromJson(Map<String, dynamic>.from(raw));
    }
    final task = await getTaskById(taskId);
    if (task == null) throw Exception('Task not found');
    return task.copyWith(status: TaskStatus.disputed, disputeReason: reason);
  }

  SubscriptionHandle subscribeToOpenTasks({
    required void Function(Map<String, dynamic>) onInsert,
    required void Function(Map<String, dynamic>) onUpdate,
    required void Function(Map<String, dynamic>) onDelete,
  }) {
    String? lastFingerprint;
    // Slower poll — avoids Jobs feed flashing every few seconds.
    final timer = Timer.periodic(const Duration(seconds: 20), (_) async {
      try {
        final tasks = await getNearbyOpenTasks();
        final fp = tasks.map((t) => '${t.id}:${t.status.dbValue}').join('|');
        if (fp == lastFingerprint) return;
        lastFingerprint = fp;
        for (final t in tasks) {
          onUpdate(t.toJson());
        }
      } catch (_) {}
    });
    return SubscriptionHandle(timer.cancel);
  }

  /// In-app task chat (client ↔ assigned helper). Persisted on the server.
  /// Pass [lang] so the API returns `display_body` in the viewer's language.
  Future<Map<String, dynamic>> getTaskChat(
    String taskId, {
    String? afterIso,
    String? lang,
  }) {
    return _api.getJson(
      '/tasks/$taskId/chat',
      query: {
        if (afterIso != null && afterIso.isNotEmpty) 'after': afterIso,
        if (lang != null && lang.isNotEmpty) 'lang': lang,
      },
    );
  }

  Future<Map<String, dynamic>> sendTaskChatMessage({
    required String taskId,
    required String body,
    String? lang,
    bool viaVoice = false,
  }) {
    return _api.postJson('/tasks/$taskId/chat', {
      'body': body,
      if (lang != null && lang.isNotEmpty) 'lang': lang,
      if (viaVoice) 'via_voice': true,
    });
  }

  Future<int> getTaskChatUnread(String taskId) async {
    final data = await _api.getJson('/tasks/$taskId/chat/unread');
    final n = data['unread_count'];
    if (n is int) return n;
    if (n is num) return n.toInt();
    return int.tryParse('$n') ?? 0;
  }

  Future<void> markTaskChatRead(String taskId) async {
    await _api.postJson('/tasks/$taskId/chat/read', {});
  }

  Future<Map<String, dynamic>> syncPreferredLang(String lang) {
    return _api.patchJson('/me', {'preferred_lang': lang});
  }

  Future<Map<String, dynamic>> impactSummary() {
    return _api.getJson('/impact/summary', auth: false);
  }

  Future<Map<String, dynamic>> resilienceStatus({
    required double lat,
    required double lon,
  }) {
    return _api.getJson(
      '/resilience/status',
      query: {'lat': '$lat', 'lon': '$lon'},
      auth: false,
    );
  }

  Future<Map<String, dynamic>> runConcierge({
    required String utterance,
    String? lang,
    double? lat,
    double? lon,
  }) {
    return _api.postJson('/agent/concierge', {
      'utterance': utterance,
      if (lang != null) 'lang': lang,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
    });
  }

  Future<Map<String, dynamic>> cloudTts({
    required String text,
    String lang = 'en',
  }) {
    return _api.postJson('/a11y/tts', {'text': text, 'lang': lang});
  }

  /// Gemini Trust Arbitrator — verdict from chat + timeline + vouch (+ receipt).
  Future<Map<String, dynamic>> runTrustReview({
    required String taskId,
    String? reason,
    String? receiptNote,
  }) {
    return _api.postJson('/tasks/$taskId/trust-review', {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      if (receiptNote != null && receiptNote.isNotEmpty)
        'receipt_note': receiptNote,
    });
  }

  Future<Map<String, dynamic>> listTrustReviews(String taskId) {
    return _api.getJson('/tasks/$taskId/trust-reviews');
  }

  SubscriptionHandle subscribeToTask({
    required String taskId,
    required void Function(Map<String, dynamic>) onUpdate,
  }) {
    // 2s so client sees completion proof almost immediately after helper submit.
    final timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final t = await getTaskById(taskId);
        if (t != null) {
          // Full task JSON — partial maps broke Task.fromJson / Active screen.
          onUpdate(t.toJson());
        }
      } catch (_) {}
    });
    // Immediate first tick — don't wait for the first interval.
    () async {
      try {
        final t = await getTaskById(taskId);
        if (t != null) onUpdate(t.toJson());
      } catch (_) {}
    }();
    return SubscriptionHandle(timer.cancel);
  }

  void unsubscribe(SubscriptionHandle channel) {
    channel.cancel();
  }
}
