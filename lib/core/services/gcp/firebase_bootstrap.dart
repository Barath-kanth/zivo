import 'package:flutter/foundation.dart';
import 'package:hyperlocal/core/constants/app_config.dart';

/// Firebase / GCP bootstrap placeholder.
///
/// Run `flutterfire configure` to generate `firebase_options.dart`, then call
/// [FirebaseBootstrap.init] from `main()` before [GcpApiClient] if you move
/// auth fully onto Firebase Auth. Until then, Cloud Run owns session tokens.
class FirebaseBootstrap {
  FirebaseBootstrap._();

  static bool get isConfigured => false;

  static Future<void> init() async {
    if (kDebugMode) {
      debugPrint(
        'FirebaseBootstrap: using Cloud Run at ${AppConfig.gcpApiBaseUrl}. '
        'Add firebase_options.dart when ready.',
      );
    }
  }
}
