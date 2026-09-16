import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/models/helper_qualification.dart';

/// Maps task categories → credentials required before helper may accept / quote.
class QualificationGate {
  QualificationGate._();

  static List<QualificationType> requiredFor(TaskCategory category) {
    switch (category) {
      case TaskCategory.driver:
        return [QualificationType.drivingLicence];
      case TaskCategory.tutoring:
        return [
          QualificationType.teachingCertificate,
          // educationDegree also accepted — see satisfies()
        ];
      case TaskCategory.babysitting:
        return [QualificationType.childCareTraining];
      case TaskCategory.elderCare:
        return [QualificationType.elderCareTraining];
      case TaskCategory.hospitalCompanion:
        return [QualificationType.firstAid];
      default:
        return const [];
    }
  }

  static bool satisfies({
    required TaskCategory category,
    required List<HelperQualification> quals,
  }) {
    final required = requiredFor(category);
    if (required.isEmpty) return true;
    final verified = quals.where((q) => q.isVerified).map((q) => q.type).toSet();

    if (category == TaskCategory.tutoring) {
      return verified.contains(QualificationType.teachingCertificate) ||
          verified.contains(QualificationType.educationDegree);
    }
    return required.every(verified.contains);
  }

  static String missingMessage({
    required TaskCategory category,
    required List<HelperQualification> quals,
  }) {
    if (satisfies(category: category, quals: quals)) return '';
    final needed = requiredFor(category).map((e) => e.label).join(' or ');
    return 'This category requires verified qualification: $needed. '
        'Add documents in Account → Qualifications. Unverified helpers cannot accept these jobs.';
  }
}
