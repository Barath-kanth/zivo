import 'oauth_url_io.dart'
    if (dart.library.html) 'oauth_url_web.dart' as impl;

/// Clears OAuth error query params before GoRouter parses the location.
void sanitizeOAuthReturnUrl() {
  if (!impl.browserUrlHasOAuthError()) return;
  impl.replaceBrowserUrl('/login');
}

String? oauthErrorFromUrl() => impl.readOAuthErrorFromBrowser();
