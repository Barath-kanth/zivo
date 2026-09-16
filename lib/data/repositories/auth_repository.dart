import 'package:hyperlocal/core/errors/app_exception.dart';
import 'package:hyperlocal/core/services/auth_service.dart';
import 'package:hyperlocal/core/services/gcp/gcp_api_client.dart';
import 'package:hyperlocal/core/utils/phone_utils.dart';
import 'package:hyperlocal/data/models/user_profile.dart';

class AuthRepository {
  AuthRepository(this._api, this._authService);

  final GcpApiClient _api;
  final AuthService _authService;

  AuthService get authService => _authService;
  GcpApiClient get api => _api;

  Stream<UserProfile?> get authStateChanges async* {
    await for (final event in _authService.onAuthStateChange) {
      if (event.session != null) {
        yield await getCurrentProfile();
      } else {
        yield null;
      }
    }
  }

  Future<void> requestPhoneOtp(String phone) =>
      _authService.requestPhoneOtp(phone);

  Future<UserProfile?> verifyPhoneOtp({
    required String phone,
    required String token,
    String? issuedCode,
  }) async {
    final response = await _authService.verifyPhoneOtp(
      phoneRaw: phone,
      token: token,
      issuedCode: issuedCode,
    );
    return _authService.cachedProfile ??
        (response.user == null
            ? null
            : UserProfile(
                id: response.user!.id,
                fullName: '',
                phone: PhoneUtils.toE164(phone),
                phoneVerifiedAt: DateTime.now().toUtc(),
                isHelperActive: false,
                kycStatus: 'verified',
              ));
  }

  Future<void> sendRecoveryEmail(String email) =>
      _authService.sendRecoveryEmail(email);

  Future<void> signOut() => _authService.signOut();

  Future<UserProfile?> getProfile(String userId) async {
    try {
      if (_authService.currentUserId == userId &&
          _authService.cachedProfile != null) {
        return _authService.cachedProfile;
      }
      final data = await _api.getJson('/me');
      return UserProfile.fromJson(
        Map<String, dynamic>.from(data['user'] as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<UserProfile?> getCurrentProfile() async {
    final id = _authService.currentUserId;
    if (id == null) return null;
    try {
      final data = await _api.getJson('/me');
      final profile = UserProfile.fromJson(
        Map<String, dynamic>.from(data['user'] as Map),
      );
      return profile;
    } catch (_) {
      return _authService.cachedProfile;
    }
  }

  Future<UserProfile?> ensureProfile({
    String? fullName,
    String? avatarUrl,
  }) async {
    final current = await getCurrentProfile();
    if (current == null) return null;
    if (fullName == null || fullName.trim().isEmpty) return current;
    return updateProfile(current.copyWith(fullName: fullName, avatarUrl: avatarUrl));
  }

  Future<UserProfile?> updateProfile(UserProfile profile) async {
    if (profile.id.startsWith('demo-')) return profile;
    final data = await _api.patchJson('/me', {
      'full_name': profile.fullName,
      if (profile.helperBio != null) 'helper_bio': profile.helperBio,
      if (profile.homeAddress != null) 'home_address': profile.homeAddress,
      'role_intent': profile.roleIntent,
      'helper_skills': profile.helperSkills,
      if (profile.guidelinesAcceptedAt != null)
        'guidelines_accepted_at':
            profile.guidelinesAcceptedAt!.toUtc().toIso8601String(),
      if (profile.kycStatus.isNotEmpty) 'kyc_status': profile.kycStatus,
      if (profile.nicNumber != null) 'nic_number': profile.nicNumber,
    });
    return UserProfile.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  Future<UserProfile?> toggleHelperMode({
    required String userId,
    required bool isHelperActive,
  }) async {
    if (userId.startsWith('demo-')) {
      throw AuthException('Demo profiles are disabled. Sign in with phone OTP.');
    }
    final data = await _api.postJson('/me/helper', {'active': isHelperActive});
    return UserProfile.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  Future<void> topUpWallet({
    required String userId,
    required double amount,
  }) async {
    if (userId.startsWith('demo-')) return;
    await _api.postJson('/wallet/topup', {'amount': amount});
  }

  Future<UserProfile?> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    await _authService.signInWithEmailPassword(
      emailOrUsername: email,
      password: password,
    );
    return getCurrentProfile();
  }

  Future<UserProfile?> signUpWithEmailPassword({
    required String email,
    required String password,
    required String fullName,
    String? username,
  }) async {
    await _authService.signUpWithEmailPassword(
      email: email,
      password: password,
      fullName: fullName,
      username: username,
    );
    return getCurrentProfile();
  }

  Future<UserProfile?> signInWithGoogle() async {
    await _authService.signInWithGoogle();
    return null;
  }
}
