import 'dart:async';

import 'package:hyperlocal/core/errors/app_exception.dart';
import 'package:hyperlocal/core/services/gcp/gcp_api_client.dart';
import 'package:hyperlocal/core/utils/phone_utils.dart';
import 'package:hyperlocal/data/models/user_profile.dart';

class GcpSession {
  const GcpSession({required this.accessToken, required this.userId});
  final String accessToken;
  final String userId;
}

class GcpUser {
  const GcpUser({required this.id, this.email, this.phone, this.metadata});
  final String id;
  final String? email;
  final String? phone;
  final Map<String, dynamic>? metadata;
}

class GcpAuthResponse {
  const GcpAuthResponse({this.user, this.session});
  final GcpUser? user;
  final GcpSession? session;
}

/// GCP-backed auth (Cloud Run). No Supabase / TextBee.
class AuthService {
  AuthService(this._api);

  final GcpApiClient _api;
  final _controller = StreamController<GcpAuthResponse>.broadcast();
  GcpSession? _session;
  GcpUser? _user;
  UserProfile? _cachedProfile;
  String? _issuedOtpPhone;
  String? _issuedOtpCode;
  String? lastOtpDeliveryWarning;
  bool textBeeSmsSent = false;

  static const int otpResendCooldownSeconds = 30;
  static const int maxClientOtpAttempts = 5;

  String? get lastFreeOtpCode => _issuedOtpCode;

  GcpSession? get currentSession => _session;
  GcpUser? get currentUser => _user;
  UserProfile? get cachedProfile => _cachedProfile;
  String? get currentUserId => _user?.id;

  Stream<GcpAuthResponse> get onAuthStateChange => _controller.stream;

  String? peekIssuedOtpCode([String? phone]) {
    if (phone == null || phone.isEmpty) return _issuedOtpCode;
    final e164 = PhoneUtils.toE164(phone);
    if (e164 == null || e164 != _issuedOtpPhone) return null;
    return _issuedOtpCode;
  }

  void bindIssuedOtp({required String phone, required String code}) {
    _issuedOtpPhone = PhoneUtils.toE164(phone) ?? phone;
    _issuedOtpCode = code;
  }

  Future<void> restoreSession() async {
    await _api.loadPersistedSession();
    if (!_api.isSignedIn) return;
    try {
      final data = await _api.getJson('/me');
      final userMap = Map<String, dynamic>.from(data['user'] as Map);
      _cachedProfile = UserProfile.fromJson(userMap);
      _user = GcpUser(
        id: _cachedProfile!.id,
        email: _cachedProfile!.email,
        phone: _cachedProfile!.phone,
      );
      _session = GcpSession(
        accessToken: _api.accessToken!,
        userId: _user!.id,
      );
      _controller.add(GcpAuthResponse(user: _user, session: _session));
    } catch (_) {
      await signOut();
    }
  }

  Future<void> requestPhoneOtp(String phone) async {
    final e164 = PhoneUtils.toE164(phone);
    if (e164 == null) throw AuthException('Invalid phone number');
    final data = await _api.postJson(
      '/auth/otp/request',
      {'phone': e164},
      auth: false,
    );
    final code = data['issuedCode'] as String?;
    if (code != null) bindIssuedOtp(phone: e164, code: code);
  }

  Future<GcpAuthResponse> verifyPhoneOtp({
    required String phoneRaw,
    required String token,
    String? issuedCode,
  }) async {
    final e164 = PhoneUtils.toE164(phoneRaw);
    if (e164 == null) throw AuthException('Invalid phone number');
    final code = token.trim().isNotEmpty ? token.trim() : (issuedCode ?? '');
    final data = await _api.postJson(
      '/auth/otp/verify',
      {'phone': e164, 'token': code},
      auth: false,
    );
    return _applyAuthPayload(data);
  }

  Future<GcpAuthResponse> signInWithEmailPassword({
    required String emailOrUsername,
    required String password,
  }) async {
    final data = await _api.postJson(
      '/auth/signin',
      {'email': emailOrUsername.trim(), 'password': password},
      auth: false,
    );
    return _applyAuthPayload(data);
  }

  Future<GcpAuthResponse> signUpWithEmailPassword({
    required String email,
    required String password,
    required String fullName,
    String? username,
  }) async {
    final data = await _api.postJson(
      '/auth/signup',
      {
        'email': email.trim(),
        'password': password,
        'full_name': fullName,
      },
      auth: false,
    );
    return _applyAuthPayload(data);
  }

  Future<void> requestEmailOtp(String email) async {
    throw AuthException(
      'Email OTP removed. Use phone OTP or email/password on GCP API.',
    );
  }

  Future<GcpAuthResponse> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    throw AuthException('Email OTP removed. Use phone OTP or email/password.');
  }

  Future<void> sendRecoveryEmail(String email) async {
    throw AuthException('Password recovery via GCP Identity Platform — wire later.');
  }

  Future<GcpAuthResponse?> signInWithGoogle() async {
    throw AuthException(
      'Google Sign-In: use Firebase Auth on GCP. For Cup demo use phone OTP or email.',
    );
  }

  Future<void> refreshSession() async {
    await restoreSession();
  }

  Future<void> signOut() async {
    _session = null;
    _user = null;
    _cachedProfile = null;
    await _api.setAccessToken(null);
    _controller.add(const GcpAuthResponse());
  }

  Future<GcpAuthResponse> _applyAuthPayload(Map<String, dynamic> data) async {
    final token = data['accessToken'] as String?;
    final userMap = Map<String, dynamic>.from(data['user'] as Map);
    if (token == null) throw AuthException('Missing access token');
    await _api.setAccessToken(token);
    _cachedProfile = UserProfile.fromJson(userMap);
    _user = GcpUser(
      id: _cachedProfile!.id,
      email: _cachedProfile!.email,
      phone: _cachedProfile!.phone,
    );
    _session = GcpSession(accessToken: token, userId: _user!.id);
    final res = GcpAuthResponse(user: _user, session: _session);
    _controller.add(res);
    return res;
  }

  void dispose() {
    _controller.close();
  }
}
