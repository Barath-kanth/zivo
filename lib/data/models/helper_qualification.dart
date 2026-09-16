import 'package:equatable/equatable.dart';

enum QualificationType {
  drivingLicence,
  teachingCertificate,
  educationDegree,
  firstAid,
  elderCareTraining,
  childCareTraining,
  tradeSkill,
  languageProficiency,
  backgroundCheckConsent,
  other;

  String get dbValue {
    switch (this) {
      case QualificationType.drivingLicence:
        return 'driving_licence';
      case QualificationType.teachingCertificate:
        return 'teaching_certificate';
      case QualificationType.educationDegree:
        return 'education_degree';
      case QualificationType.firstAid:
        return 'first_aid';
      case QualificationType.elderCareTraining:
        return 'elder_care_training';
      case QualificationType.childCareTraining:
        return 'child_care_training';
      case QualificationType.tradeSkill:
        return 'trade_skill';
      case QualificationType.languageProficiency:
        return 'language_proficiency';
      case QualificationType.backgroundCheckConsent:
        return 'background_check_consent';
      case QualificationType.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case QualificationType.drivingLicence:
        return 'Driving licence';
      case QualificationType.teachingCertificate:
        return 'Teaching certificate';
      case QualificationType.educationDegree:
        return 'Education / degree';
      case QualificationType.firstAid:
        return 'First aid';
      case QualificationType.elderCareTraining:
        return 'Elder-care training';
      case QualificationType.childCareTraining:
        return 'Child-care training';
      case QualificationType.tradeSkill:
        return 'Trade / technical skill';
      case QualificationType.languageProficiency:
        return 'Language proficiency';
      case QualificationType.backgroundCheckConsent:
        return 'Background-check consent';
      case QualificationType.other:
        return 'Other credential';
    }
  }

  String get hint {
    switch (this) {
      case QualificationType.drivingLicence:
        return 'Required before accepting Driver jobs. Upload a clear licence photo.';
      case QualificationType.teachingCertificate:
        return 'Required for Tutoring. Upload certificate or registration.';
      case QualificationType.educationDegree:
        return 'Supports Tutoring credibility. Upload degree or transcript cover.';
      case QualificationType.childCareTraining:
        return 'Required for Babysitting. KYC must also be verified.';
      case QualificationType.elderCareTraining:
        return 'Required for Elder Care. You are not a licensed clinician unless stated.';
      case QualificationType.backgroundCheckConsent:
        return 'Consent for lawful identity checks. Does not replace police clearance.';
      default:
        return 'Upload a verifiable document. Fake credentials are prohibited.';
    }
  }

  bool get requiresDocument =>
      this == QualificationType.drivingLicence ||
      this == QualificationType.teachingCertificate ||
      this == QualificationType.educationDegree ||
      this == QualificationType.childCareTraining ||
      this == QualificationType.elderCareTraining;

  static QualificationType fromDb(String v) {
    switch (v) {
      case 'driving_licence':
        return QualificationType.drivingLicence;
      case 'teaching_certificate':
        return QualificationType.teachingCertificate;
      case 'education_degree':
        return QualificationType.educationDegree;
      case 'first_aid':
        return QualificationType.firstAid;
      case 'elder_care_training':
        return QualificationType.elderCareTraining;
      case 'child_care_training':
        return QualificationType.childCareTraining;
      case 'trade_skill':
        return QualificationType.tradeSkill;
      case 'language_proficiency':
        return QualificationType.languageProficiency;
      case 'background_check_consent':
        return QualificationType.backgroundCheckConsent;
      default:
        return QualificationType.other;
    }
  }
}

class HelperQualification extends Equatable {
  const HelperQualification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    this.issuer,
    this.credentialId,
    this.documentPath,
    this.status = 'pending',
    this.rejectionReason,
    this.expiresAt,
    this.verifiedAt,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final QualificationType type;
  final String title;
  final String? issuer;
  final String? credentialId;
  final String? documentPath;
  final String status;
  final String? rejectionReason;
  final DateTime? expiresAt;
  final DateTime? verifiedAt;
  final DateTime createdAt;

  bool get isVerified => status == 'verified';
  bool get isPending => status == 'pending';

  factory HelperQualification.fromJson(Map<String, dynamic> json) {
    return HelperQualification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: QualificationType.fromDb(json['qual_type'] as String? ?? 'other'),
      title: json['title'] as String? ?? '',
      issuer: json['issuer'] as String?,
      credentialId: json['credential_id'] as String?,
      documentPath: json['document_path'] as String?,
      status: json['status'] as String? ?? 'pending',
      rejectionReason: json['rejection_reason'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      verifiedAt: json['verified_at'] != null
          ? DateTime.tryParse(json['verified_at'].toString())
          : null,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, userId, type, title, status];
}
