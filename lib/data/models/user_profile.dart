import 'package:equatable/equatable.dart';
import 'package:hyperlocal/core/utils/phone_utils.dart';

class UserProfile extends Equatable {
  const UserProfile({
    required this.id,
    required this.fullName,
    this.avatarUrl,
    this.phone,
    this.phoneVerifiedAt,
    this.email,
    this.emailVerifiedAt,
    required this.isHelperActive,
    this.helperBio,
    this.helperSkills = const [],
    this.ratingAsClient = 5.0,
    this.ratingAsHelper = 5.0,
    this.totalTasksPosted = 0,
    this.totalTasksHelped = 0,
    this.walletBalance = 0.0,
    this.escrowBalance = 0.0,
    this.helperEarnings = 0.0,
    this.nicNumber,
    this.nicImageUrl,
    this.selfieImageUrl,
    this.homeAddress,
    this.kycStatus = 'unverified',
    this.kycRejectionReason,
    this.kycSubmittedAt,
    this.kycVerifiedAt,
    this.dateOfBirth,
    this.roleIntent = 'client',
    this.termsAcceptedAt,
    this.communityGuidelinesVersion,
    this.guidelinesAcceptedAt,
  });

  final String id;
  final String fullName;
  final String? avatarUrl;
  final String? phone;
  final DateTime? phoneVerifiedAt;
  final String? email;
  final DateTime? emailVerifiedAt;
  final bool isHelperActive;
  final String? helperBio;
  final List<String> helperSkills;
  final double ratingAsClient;
  final double ratingAsHelper;
  final int totalTasksPosted;
  final int totalTasksHelped;
  final double walletBalance;
  final double escrowBalance;
  final double helperEarnings;
  final String? nicNumber;
  final String? nicImageUrl;
  final String? selfieImageUrl;
  final String? homeAddress;
  final String kycStatus;
  final String? kycRejectionReason;
  final DateTime? kycSubmittedAt;
  final DateTime? kycVerifiedAt;
  final DateTime? dateOfBirth;
  final String roleIntent;
  final DateTime? termsAcceptedAt;
  final String? communityGuidelinesVersion;
  final DateTime? guidelinesAcceptedAt;

  bool get isPhoneVerified =>
      phoneVerifiedAt != null || (phone != null && phone!.startsWith('+94'));

  bool get isKycVerified => kycStatus == 'verified';
  bool get isKycPending => kycStatus == 'pending';
  bool get canActivateHelper => isKycVerified && guidelinesAcceptedAt != null;

  /// Verified users cannot post/help until re-approved after identity edits.
  bool get canPostOrHelp => isKycVerified;

  /// Browse-first guest (not signed in).
  bool get isGuest => id == guestId;

  static const String guestId = 'guest';

  /// Placeholder names from DB trigger / anonymous signup (not a real identity).
  bool get hasPlaceholderName {
    final n = fullName.trim().toLowerCase();
    return n.isEmpty ||
        n == 'user' ||
        n == 'guest' ||
        n == 'profile' ||
        n == 'your profile';
  }

  /// Name for UI: real full name, else phone, else email local-part.
  String get displayLabel {
    if (!hasPlaceholderName) return fullName.trim();
    if (phone != null && phone!.trim().isNotEmpty) {
      return PhoneUtils.formatDisplay(phone!);
    }
    if (email != null && email!.contains('@')) {
      return email!.split('@').first;
    }
    return 'Account';
  }

  /// First token for compact chips (home header).
  String get displayShort {
    final label = displayLabel;
    if (hasPlaceholderName && phone != null) {
      final n = PhoneUtils.nationalDigits(phone!);
      if (n.length == 9) {
        return '${n.substring(0, 2)} ${n.substring(2, 5)} ${n.substring(5)}';
      }
    }
    final parts = label.split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.first : label;
  }

  String get displayInitial {
    if (!hasPlaceholderName && fullName.trim().isNotEmpty) {
      return fullName.trim()[0].toUpperCase();
    }
    if (phone != null) {
      final n = PhoneUtils.nationalDigits(phone!);
      if (n.isNotEmpty) return n[0];
    }
    final label = displayLabel;
    return label.isNotEmpty ? label[0].toUpperCase() : '?';
  }

  /// KYC + guidelines required only for Helper mode (Uber-style).
  bool get needsKycForHelper => !canActivateHelper;

  /// True when identity docs were never submitted (show onboarding for Helper).
  bool get needsOnboarding {
    if (isGuest) return false;
    if (guidelinesAcceptedAt == null) return true;
    if (nicNumber == null || nicNumber!.isEmpty) return true;
    if (kycStatus == 'unverified') return true;
    return false;
  }

  static UserProfile guest() => const UserProfile(
        id: guestId,
        fullName: 'Guest',
        isHelperActive: false,
      );

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        fullName: json['full_name'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String?,
        phone: json['phone'] as String?,
        phoneVerifiedAt: _parseDate(json['phone_verified_at']),
        email: json['email'] as String?,
        emailVerifiedAt: _parseDate(json['email_verified_at']),
        isHelperActive: json['is_helper_active'] as bool? ?? false,
        helperBio: json['helper_bio'] as String?,
        helperSkills: (json['helper_skills'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        ratingAsClient: (json['rating_as_client'] as num?)?.toDouble() ?? 5.0,
        ratingAsHelper: (json['rating_as_helper'] as num?)?.toDouble() ?? 5.0,
        totalTasksPosted: json['total_tasks_posted'] as int? ?? 0,
        totalTasksHelped: json['total_tasks_helped'] as int? ?? 0,
        walletBalance: (json['wallet_balance'] as num?)?.toDouble() ?? 0.0,
        escrowBalance: (json['escrow_balance'] as num?)?.toDouble() ?? 0.0,
        helperEarnings: (json['helper_earnings'] as num?)?.toDouble() ?? 0.0,
        nicNumber: json['nic_number'] as String?,
        nicImageUrl: json['nic_image_url'] as String?,
        selfieImageUrl: json['selfie_image_url'] as String?,
        homeAddress: json['home_address'] as String?,
        kycStatus: json['kyc_status'] as String? ?? 'unverified',
        kycRejectionReason: json['kyc_rejection_reason'] as String?,
        kycSubmittedAt: _parseDate(json['kyc_submitted_at']),
        kycVerifiedAt: _parseDate(json['kyc_verified_at']),
        dateOfBirth: _parseDate(json['date_of_birth']),
        roleIntent: json['role_intent'] as String? ?? 'client',
        termsAcceptedAt: _parseDate(json['terms_accepted_at']),
        communityGuidelinesVersion:
            json['community_guidelines_version'] as String?,
        guidelinesAcceptedAt: _parseDate(json['guidelines_accepted_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'avatar_url': avatarUrl,
        'phone': phone,
        'phone_verified_at': phoneVerifiedAt?.toIso8601String(),
        'email': email,
        'email_verified_at': emailVerifiedAt?.toIso8601String(),
        'is_helper_active': isHelperActive,
        'helper_bio': helperBio,
        'helper_skills': helperSkills,
        'rating_as_client': ratingAsClient,
        'rating_as_helper': ratingAsHelper,
        'total_tasks_posted': totalTasksPosted,
        'total_tasks_helped': totalTasksHelped,
        'wallet_balance': walletBalance,
        'escrow_balance': escrowBalance,
        'helper_earnings': helperEarnings,
        'nic_number': nicNumber,
        'nic_image_url': nicImageUrl,
        'selfie_image_url': selfieImageUrl,
        'home_address': homeAddress,
        'kyc_status': kycStatus,
        'kyc_rejection_reason': kycRejectionReason,
        'kyc_submitted_at': kycSubmittedAt?.toIso8601String(),
        'kyc_verified_at': kycVerifiedAt?.toIso8601String(),
        'date_of_birth': dateOfBirth?.toIso8601String(),
        'role_intent': roleIntent,
        'terms_accepted_at': termsAcceptedAt?.toIso8601String(),
        'community_guidelines_version': communityGuidelinesVersion,
        'guidelines_accepted_at': guidelinesAcceptedAt?.toIso8601String(),
      };

  UserProfile copyWith({
    String? fullName,
    String? avatarUrl,
    String? phone,
    DateTime? phoneVerifiedAt,
    String? email,
    bool? isHelperActive,
    String? helperBio,
    List<String>? helperSkills,
    double? walletBalance,
    double? escrowBalance,
    double? helperEarnings,
    String? nicNumber,
    String? nicImageUrl,
    String? selfieImageUrl,
    String? homeAddress,
    String? kycStatus,
    String? kycRejectionReason,
    DateTime? kycSubmittedAt,
    DateTime? kycVerifiedAt,
    DateTime? dateOfBirth,
    String? roleIntent,
    DateTime? guidelinesAcceptedAt,
    String? communityGuidelinesVersion,
  }) {
    return UserProfile(
      id: id,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phone: phone ?? this.phone,
      phoneVerifiedAt: phoneVerifiedAt ?? this.phoneVerifiedAt,
      email: email ?? this.email,
      emailVerifiedAt: emailVerifiedAt ?? this.emailVerifiedAt,
      isHelperActive: isHelperActive ?? this.isHelperActive,
      helperBio: helperBio ?? this.helperBio,
      helperSkills: helperSkills ?? this.helperSkills,
      ratingAsClient: ratingAsClient,
      ratingAsHelper: ratingAsHelper,
      totalTasksPosted: totalTasksPosted,
      totalTasksHelped: totalTasksHelped,
      walletBalance: walletBalance ?? this.walletBalance,
      escrowBalance: escrowBalance ?? this.escrowBalance,
      helperEarnings: helperEarnings ?? this.helperEarnings,
      nicNumber: nicNumber ?? this.nicNumber,
      nicImageUrl: nicImageUrl ?? this.nicImageUrl,
      selfieImageUrl: selfieImageUrl ?? this.selfieImageUrl,
      homeAddress: homeAddress ?? this.homeAddress,
      kycStatus: kycStatus ?? this.kycStatus,
      kycRejectionReason: kycRejectionReason ?? this.kycRejectionReason,
      kycSubmittedAt: kycSubmittedAt ?? this.kycSubmittedAt,
      kycVerifiedAt: kycVerifiedAt ?? this.kycVerifiedAt,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      roleIntent: roleIntent ?? this.roleIntent,
      termsAcceptedAt: this.termsAcceptedAt,
      communityGuidelinesVersion:
          communityGuidelinesVersion ?? this.communityGuidelinesVersion,
      guidelinesAcceptedAt: guidelinesAcceptedAt ?? this.guidelinesAcceptedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        fullName,
        avatarUrl,
        phone,
        phoneVerifiedAt,
        email,
        isHelperActive,
        helperBio,
        helperSkills,
        ratingAsClient,
        ratingAsHelper,
        totalTasksPosted,
        totalTasksHelped,
        walletBalance,
        escrowBalance,
        helperEarnings,
        nicNumber,
        nicImageUrl,
        selfieImageUrl,
        homeAddress,
        kycStatus,
        kycRejectionReason,
        dateOfBirth,
        roleIntent,
        guidelinesAcceptedAt,
        communityGuidelinesVersion,
      ];
}
