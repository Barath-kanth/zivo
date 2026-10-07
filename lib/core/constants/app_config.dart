import 'package:flutter/foundation.dart';

/// Runtime configuration via `--dart-define` (GCP / Firebase Hosting).
///
/// ```
/// flutter run -d chrome --web-port=7357 \
///   --dart-define=GCP_API_BASE_URL=http://localhost:8080
/// ```
abstract class AppConfig {
  AppConfig._();

  static const String currencyCode = String.fromEnvironment(
    'CURRENCY_CODE',
    defaultValue: 'LKR',
  );

  static const String defaultCountryCode = String.fromEnvironment(
    'DEFAULT_COUNTRY_CODE',
    defaultValue: '+94',
  );

  static const String marketName = String.fromEnvironment(
    'MARKET_NAME',
    defaultValue: 'Sri Lanka',
  );

  static const String gcpApiBaseUrl = String.fromEnvironment(
    'GCP_API_BASE_URL',
    defaultValue: 'https://zivo-api-ihp5vjzpsa-el.a.run.app',
  );

  static const String _dispatchRadiusKm = String.fromEnvironment(
    'DISPATCH_RADIUS_KM',
    defaultValue: '80.0',
  );

  static const String _platformFeePercent = String.fromEnvironment(
    'PLATFORM_FEE_PERCENT',
    defaultValue: '10.0',
  );

  static double get dispatchRadiusKm =>
      double.tryParse(_dispatchRadiusKm) ?? 5.0;

  static double get platformFeePercent =>
      double.tryParse(_platformFeePercent) ?? 10.0;

  /// Local/dev OTP issued by Cloud Run (no SMS vendor).
  static const bool forceFreeOtp = bool.fromEnvironment(
    'FORCE_FREE_OTP',
    defaultValue: true,
  );

  static const bool enableDemoMode = bool.fromEnvironment(
    'ENABLE_DEMO_MODE',
    defaultValue: false,
  );

  static const bool useRealGps = bool.fromEnvironment(
    'USE_REAL_GPS',
    defaultValue: true,
  );

  static const bool pilotMode = bool.fromEnvironment(
    'PILOT_MODE',
    defaultValue: false,
  );

  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static const String legalBaseUrl = String.fromEnvironment(
    'LEGAL_BASE_URL',
    defaultValue: '',
  );

  static String? get privacyPolicyUrl =>
      legalBaseUrl.isEmpty ? null : '$legalBaseUrl/privacy.html';

  static String? get termsUrl =>
      legalBaseUrl.isEmpty ? null : '$legalBaseUrl/terms.html';

  static String? get accountDeletionUrl =>
      legalBaseUrl.isEmpty ? null : '$legalBaseUrl/account-deletion.html';

  static const bool forbidCashToHelper = true;

  static bool requiresPurchaseTrust(String categoryName) {
    return categoryName == 'groceryRun' || categoryName == 'errandRun';
  }

  static bool get demoAllowed =>
      !pilotMode && enableDemoMode && (kDebugMode || forceFreeOtp);

  static bool get freeOtpAllowed =>
      !pilotMode && forceFreeOtp && (kDebugMode || !kReleaseMode);

  static String money(num amount, {int decimals = 0}) {
    return '$currencyCode ${amount.toStringAsFixed(decimals)}';
  }
}
