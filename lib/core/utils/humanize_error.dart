import 'dart:convert';

/// Turn API / Zod / JSON error payloads into short user-facing copy.
String humanizeError(Object? error, {int? statusCode}) {
  if (error == null) return _fallback(statusCode);

  if (error is String) {
    final t = error.trim();
    if (t.isEmpty) return _fallback(statusCode);
    if (_looksLikeJson(t)) {
      return _fromJsonish(t) ?? _fallback(statusCode);
    }
    return t
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^AppAuthException:\s*'), '')
        .trim();
  }

  if (error is Map) {
    final mapped = _fromMap(Map<String, dynamic>.from(error));
    if (mapped != null) return mapped;
  }

  final s = error.toString().trim();
  if (_looksLikeJson(s)) return _fromJsonish(s) ?? _fallback(statusCode);
  if (s.contains('NotAllowedError') ||
      s.contains('Permission dismissed') ||
      s.contains('PermissionDenied')) {
    return 'Microphone permission blocked. Allow Microphone for this site in the browser address bar, then tap Start recording again.';
  }
  final cleaned = s
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceFirst(RegExp(r'^StateError:\s*'), '')
      .replaceFirst(RegExp(r'^Bad state:\s*'), '')
      .trim();
  return cleaned.isEmpty ? _fallback(statusCode) : cleaned;
}

String _fallback(int? statusCode) {
  if (statusCode == 401 || statusCode == 403) {
    return 'Please sign in again and try once more.';
  }
  if (statusCode == 429) {
    return 'Too many requests — wait a moment and try again.';
  }
  if (statusCode != null && statusCode >= 500) {
    return 'Server issue — please try again in a minute.';
  }
  return 'Something went wrong. Please try again.';
}

bool _looksLikeJson(String t) {
  final s = t.trim();
  return s.startsWith('{') ||
      s.startsWith('[') ||
      s.contains('"code":') ||
      s.contains('formErrors') ||
      s.contains('fieldErrors') ||
      s.contains('"too_big"') ||
      s.contains('"too_small"');
}

String? _fromJsonish(String raw) {
  try {
    final startArr = raw.indexOf('[');
    final startObj = raw.indexOf('{');
    final start = startArr >= 0 && (startObj < 0 || startArr < startObj)
        ? startArr
        : startObj;
    if (start < 0) return null;
    final slice = raw.substring(start);
    final decoded = jsonDecode(slice);
    if (decoded is List) {
      final parts = <String>[];
      for (final item in decoded) {
        if (item is Map) {
          final msg = _issueMessage(Map<String, dynamic>.from(item));
          if (msg != null) parts.add(msg);
        }
      }
      if (parts.isNotEmpty) return parts.join('. ');
    }
    if (decoded is Map) {
      return _fromMap(Map<String, dynamic>.from(decoded));
    }
  } catch (_) {/* fall through */}
  return null;
}

String? _fromMap(Map<String, dynamic> map) {
  final err = map['error'];
  if (err is String && err.trim().isNotEmpty) {
    if (_looksLikeJson(err)) return _fromJsonish(err) ?? err;
    return err;
  }
  if (err is Map) {
    final nested = _fromMap(Map<String, dynamic>.from(err));
    if (nested != null) return nested;
  }
  if (err is List) {
    final parts = err
        .whereType<Map>()
        .map((e) => _issueMessage(Map<String, dynamic>.from(e)))
        .whereType<String>()
        .toList();
    if (parts.isNotEmpty) return parts.join('. ');
  }

  final fieldErrors = map['fieldErrors'];
  if (fieldErrors is Map) {
    final parts = <String>[];
    fieldErrors.forEach((key, value) {
      final field = key.toString();
      final msg = value is List
          ? value.map((e) => e.toString()).join(', ')
          : value?.toString() ?? '';
      final friendly = _friendlyField(field, msg);
      if (friendly.isNotEmpty) parts.add(friendly);
    });
    if (parts.isNotEmpty) return parts.join('. ');
  }

  final formErrors = map['formErrors'];
  if (formErrors is List && formErrors.isNotEmpty) {
    return formErrors.map((e) => e.toString()).join('. ');
  }

  return _issueMessage(map);
}

String? _issueMessage(Map<String, dynamic> issue) {
  final path = (issue['path'] is List)
      ? (issue['path'] as List).map((e) => e.toString()).join('.')
      : issue['path']?.toString() ?? '';
  final code = issue['code']?.toString() ?? '';
  final message = issue['message']?.toString() ?? '';
  final friendly = _friendlyField(path, message, code: code, issue: issue);
  return friendly.isEmpty ? null : friendly;
}

String _friendlyField(
  String path,
  String message, {
  String code = '',
  Map<String, dynamic>? issue,
}) {
  final p = path.toLowerCase();
  if (p.contains('client_boost')) {
    return 'Tip can’t be more than LKR 20,000';
  }
  if (p.contains('goods_budget')) {
    return 'Goods budget is too high — try a smaller amount';
  }
  if (p.contains('description')) {
    return message.isNotEmpty
        ? message
        : 'Please add a clearer task description';
  }
  if (p.contains('travel_km')) {
    return 'Travel distance looks too far for this task';
  }
  if (code == 'too_big') {
    final max = issue?['maximum'];
    if (max != null) return 'That amount is too high (max $max)';
    return 'That value is too high';
  }
  if (code == 'too_small') {
    return message.isNotEmpty ? message : 'That value is too small';
  }
  if (message.isNotEmpty) return message;
  return '';
}
