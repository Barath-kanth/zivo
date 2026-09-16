/// App-level auth/API errors (replaces supabase AuthException).
class AppAuthException implements Exception {
  const AppAuthException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Backward-compatible alias used across UI/repos.
typedef AuthException = AppAuthException;
