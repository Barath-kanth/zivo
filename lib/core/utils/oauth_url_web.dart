// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

void replaceBrowserUrl(String path) {
  html.window.history.replaceState(null, '', path);
}

String? readOAuthErrorFromBrowser() {
  final uri = Uri.parse(html.window.location.href);
  final desc = uri.queryParameters['error_description'] ??
      uri.queryParameters['error'];
  if (desc == null || desc.isEmpty) return null;
  return Uri.decodeComponent(desc.replaceAll('+', ' '));
}

bool browserUrlHasOAuthError() {
  final uri = Uri.parse(html.window.location.href);
  return uri.queryParameters.containsKey('error') ||
      uri.queryParameters.containsKey('error_code') ||
      uri.queryParameters.containsKey('error_description');
}
