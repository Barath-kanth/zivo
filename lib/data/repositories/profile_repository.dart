import 'dart:typed_data';

import 'package:hyperlocal/core/services/profile_service.dart';
import 'package:hyperlocal/data/models/user_profile.dart';

class ProfileRepository {
  ProfileRepository(this._profileService);

  final ProfileService _profileService;

  Future<UserProfile?> getProfile(String userId) =>
      _profileService.getProfile(userId);

  Future<String> uploadKycDocument({
    required String userId,
    required String docType,
    required Uint8List bytes,
  }) =>
      _profileService.uploadKycDocument(
        userId: userId,
        docType: docType,
        bytes: bytes,
      );

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
  }) =>
      _profileService.submitKyc(
        fullName: fullName,
        nicNumber: nicNumber,
        dateOfBirth: dateOfBirth,
        roleIntent: roleIntent,
        avatarUrl: avatarUrl,
        nicImageUrl: nicImageUrl,
        selfieImageUrl: selfieImageUrl,
        helperBio: helperBio,
        helperSkills: helperSkills,
      );

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
  }) =>
      _profileService.requestIdentityChange(
        fullName: fullName,
        homeAddress: homeAddress,
        nicNumber: nicNumber,
        dateOfBirth: dateOfBirth,
        avatarUrl: avatarUrl,
        nicImageUrl: nicImageUrl,
        selfieImageUrl: selfieImageUrl,
        helperBio: helperBio,
        helperSkills: helperSkills,
      );

  Future<void> updateHomeAddress(String address) =>
      _profileService.updateHomeAddress(address);

  Future<List<Map<String, dynamic>>> listPendingKyc() =>
      _profileService.listPendingKyc();

  Future<void> reviewKycDecision({
    required String userId,
    required String status,
    String? reason,
  }) =>
      _profileService.reviewKycDecision(
        userId: userId,
        status: status,
        reason: reason,
      );

  Future<void> logPolicyViolation({
    required String matchedRule,
    required String snippet,
  }) =>
      _profileService.logPolicyViolation(
        matchedRule: matchedRule,
        snippet: snippet,
      );
}
