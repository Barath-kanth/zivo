import 'dart:typed_data';

import 'package:hyperlocal/core/constants/community_guidelines.dart';
import 'package:hyperlocal/core/errors/app_exception.dart';
import 'package:hyperlocal/core/services/auth_service.dart';
import 'package:hyperlocal/core/services/gcp/gcp_api_client.dart';
import 'package:hyperlocal/core/services/kyc/kyc_verifier.dart';
import 'package:hyperlocal/core/utils/nic_validator.dart';
import 'package:hyperlocal/data/models/user_profile.dart';

/// Profile + KYC via GCP API (no Supabase Storage).
class ProfileService {
  ProfileService(this._api, this._auth, this._kycVerifier);

  final GcpApiClient _api;
  final AuthService _auth;
  final KycVerifier _kycVerifier;

  Future<UserProfile?> getProfile(String userId) async {
    try {
      if (_auth.currentUserId == userId) {
        final data = await _api.getJson('/me');
        return UserProfile.fromJson(
          Map<String, dynamic>.from(data['user'] as Map),
        );
      }
      return null;
    } catch (_) {
      return _auth.cachedProfile;
    }
  }

  Future<String> uploadKycDocument({
    required String userId,
    required String docType,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    if (userId.startsWith('demo-')) {
      throw const AuthException('Demo disabled');
    }
    // Cup: store as data-URI placeholder until Cloud Storage is wired.
    return 'gcp://kyc/$userId/$docType-${DateTime.now().millisecondsSinceEpoch}.jpg';
  }

  Future<UserProfile> submitKyc({
    required String fullName,
    required String nicNumber,
    required DateTime dateOfBirth,
    required String roleIntent,
    required String avatarUrl,
    required String nicImageUrl,
    required String selfieImageUrl,
    String? helperBio,
    List<String> helperSkills = const [],
    String guidelinesVersion = CommunityGuidelines.currentVersion,
  }) async {
    final nic = NicValidator.normalize(nicNumber);
    if (!NicValidator.isValid(nic)) {
      throw const AuthException('Invalid Sri Lanka NIC');
    }
    final age = DateTime.now().difference(dateOfBirth).inDays ~/ 365;
    if (age < 18) {
      throw const AuthException('You must be 18 or older');
    }
    final userId = _auth.currentUserId;
    if (userId == null) throw const AuthException('Not authenticated');

    await _kycVerifier.submitForReview(
      userId: userId,
      nicNumber: nic,
      nicImageUrl: nicImageUrl,
      selfieImageUrl: selfieImageUrl,
    );

    final data = await _api.patchJson('/me', {
      'full_name': fullName.trim(),
      'nic_number': nic,
      'role_intent': roleIntent,
      'helper_bio': helperBio,
      'helper_skills': helperSkills,
      'kyc_status': 'verified',
      'guidelines_accepted_at': DateTime.now().toUtc().toIso8601String(),
    });
    return UserProfile.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  Future<UserProfile> requestIdentityChange({
    String? fullName,
    String? homeAddress,
    String? nicNumber,
    DateTime? dateOfBirth,
    String? avatarUrl,
    String? nicImageUrl,
    String? selfieImageUrl,
    String? helperBio,
    List<String>? helperSkills,
  }) async {
    final data = await _api.patchJson('/me', {
      if (fullName != null) 'full_name': fullName,
      if (homeAddress != null) 'home_address': homeAddress,
      if (nicNumber != null) 'nic_number': nicNumber,
      if (helperBio != null) 'helper_bio': helperBio,
      if (helperSkills != null) 'helper_skills': helperSkills,
      'kyc_status': 'pending',
    });
    return UserProfile.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  Future<void> updateHomeAddress(String address) async {
    await _api.patchJson('/me', {'home_address': address.trim()});
  }

  Future<List<Map<String, dynamic>>> listPendingKyc() async {
    return [];
  }

  Future<void> reviewKycDecision({
    required String userId,
    required String status,
    String? reason,
  }) async {
    // Ops: patch via admin token later; Cup stubs verified at submit.
  }

  Future<void> logPolicyViolation({
    required String matchedRule,
    required String snippet,
    String surface = 'task_create',
  }) async {
    // Logged server-side when safety blocks on Cloud Run.
  }
}
