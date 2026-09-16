import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/errors/app_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// HTTP client for Zivo Cloud Run API (GCP-only backend).
class GcpApiClient {
  GcpApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        baseUrl = baseUrl ?? AppConfig.gcpApiBaseUrl;

  final http.Client _http;
  final String baseUrl;
  String? _accessToken;

  String? get accessToken => _accessToken;
  bool get isSignedIn => _accessToken != null && _accessToken!.isNotEmpty;

  Future<void> loadPersistedSession() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('gcp_access_token');
  }

  Future<void> setAccessToken(String? token) async {
    _accessToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove('gcp_access_token');
    } else {
      await prefs.setString('gcp_access_token', token);
    }
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Map<String, String> _headers({bool json = true, bool auth = true}) {
    return {
      if (json) 'Content-Type': 'application/json',
      if (auth && _accessToken != null) 'Authorization': 'Bearer $_accessToken',
    };
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
    bool auth = true,
  }) async {
    final res = await _http.get(_uri(path, query), headers: _headers(auth: auth));
    return _decode(res);
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final res = await _http.post(
      _uri(path),
      headers: _headers(auth: auth),
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await _http.patch(
      _uri(path),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Map<String, String> fields,
    List<int>? fileBytes,
    String fileField = 'receipt',
    String filename = 'receipt.jpg',
  }) async {
    final req = http.MultipartRequest('POST', _uri(path));
    if (_accessToken != null) {
      req.headers['Authorization'] = 'Bearer $_accessToken';
    }
    req.fields.addAll(fields);
    if (fileBytes != null) {
      req.files.add(
        http.MultipartFile.fromBytes(fileField, fileBytes, filename: filename),
      );
    }
    final streamed = await _http.send(req);
    final res = await http.Response.fromStream(streamed);
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> body = {};
    if (res.body.isNotEmpty) {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        body = decoded;
      } else {
        body = {'data': decoded};
      }
    }
    if (res.statusCode >= 400) {
      final err = body['error'];
      final message = err is String
          ? err
          : err?.toString() ?? 'Request failed (${res.statusCode})';
      throw AppAuthException(message, statusCode: res.statusCode);
    }
    return body;
  }
}
