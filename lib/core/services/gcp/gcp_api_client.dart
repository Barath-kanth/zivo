import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/errors/app_exception.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
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

  /// No request may hang forever (a stalled Vertex call used to leave the UI spinning for minutes).
  static const _timeout = Duration(seconds: 40);
  static const _uploadTimeout = Duration(seconds: 50);

  Future<T> _bounded<T>(Future<T> f, Duration limit) async {
    try {
      return await f.timeout(limit);
    } on TimeoutException {
      throw AppAuthException(
        'This is taking longer than expected. Please try again in a moment.',
        statusCode: 408,
      );
    }
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
    bool auth = true,
  }) async {
    final res = await _bounded(_http.get(_uri(path, query), headers: _headers(auth: auth)), _timeout);
    return _decode(res);
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final res = await _bounded(
      _http.post(
        _uri(path),
        headers: _headers(auth: auth),
        body: jsonEncode(body),
      ),
      _timeout,
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
    String? contentType,
    List<({List<int> bytes, String field, String filename, String? contentType})>?
        extraFiles,
  }) async {
    final req = http.MultipartRequest('POST', _uri(path));
    if (_accessToken != null) {
      req.headers['Authorization'] = 'Bearer $_accessToken';
    }
    req.fields.addAll(fields);
    void addFile({
      required List<int> bytes,
      required String field,
      required String name,
      String? type,
    }) {
      final declared = type?.trim() ?? '';
      final MediaType mime;
      if (declared.startsWith('audio/')) {
        mime = MediaType.parse(declared);
      } else {
        mime = _sniffImageMediaType(bytes, type, name);
      }
      final safeName = name.contains('.')
          ? name
          : declared.startsWith('audio/')
              ? 'clip.webm'
              : 'photo.${mime.subtype == 'jpeg' ? 'jpg' : mime.subtype}';
      req.files.add(
        http.MultipartFile.fromBytes(
          field,
          bytes,
          filename: safeName,
          contentType: mime,
        ),
      );
    }

    if (fileBytes != null) {
      addFile(
        bytes: fileBytes,
        field: fileField,
        name: filename,
        type: contentType,
      );
    }
    for (final f in extraFiles ?? const []) {
      addFile(
        bytes: f.bytes,
        field: f.field,
        name: f.filename,
        type: f.contentType,
      );
    }
    final res = await _bounded(
      _http.send(req).then(http.Response.fromStream),
      _uploadTimeout,
    );
    return _decode(res);
  }

  /// Upload a task reference photo (any category). Returns `{url, path}`.
  Future<Map<String, String>> uploadTaskPhoto({
    required List<int> bytes,
    String filename = 'photo.jpg',
  }) async {
    final data = await postMultipart(
      '/uploads/photo',
      fields: const {},
      fileBytes: bytes,
      fileField: 'photo',
      filename: filename,
    );
    final url = data['url'] as String?;
    final path = data['path'] as String?;
    if (url == null || url.isEmpty) {
      throw AppAuthException('Upload did not return a URL');
    }
    return {
      'url': url,
      if (path != null && path.isNotEmpty) 'path': path,
    };
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
      final err = body['error'] ?? body;
      final message = humanizeError(err, statusCode: res.statusCode);
      throw AppAuthException(message, statusCode: res.statusCode);
    }
    return body;
  }

  /// Vertex rejects application/octet-stream — sniff JPEG/PNG/WebP.
  MediaType _sniffImageMediaType(
    List<int> bytes,
    String? declared,
    String filename,
  ) {
    final d = (declared ?? '').toLowerCase();
    if (d.startsWith('image/')) {
      final parts = d.split('/');
      if (parts.length == 2 && parts[1].isNotEmpty) {
        return MediaType('image', parts[1] == 'jpg' ? 'jpeg' : parts[1]);
      }
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return MediaType('image', 'jpeg');
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return MediaType('image', 'png');
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return MediaType('image', 'webp');
    }
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('image', 'jpeg');
  }
}
