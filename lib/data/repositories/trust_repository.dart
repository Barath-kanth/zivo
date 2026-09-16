import 'package:hyperlocal/core/errors/app_exception.dart';
import 'package:hyperlocal/core/services/policy/community_policy_engine.dart';
import 'package:hyperlocal/data/models/helper_qualification.dart';
import 'package:hyperlocal/data/models/user_review.dart';

/// Trust layer — in-memory for Cup (Firestore later). No Supabase.
class TrustRepository {
  TrustRepository();

  static final List<HelperQualification> _quals = [];
  static final List<UserReview> _reviews = [];
  static final List<JobQuote> _quotes = [];

  Future<List<HelperQualification>> getQualifications(String userId) async {
    return List.of(_quals.where((q) => q.userId == userId));
  }

  Future<HelperQualification> submitQualification({
    required String userId,
    required QualificationType type,
    required String title,
    String? issuer,
    String? credentialId,
    String? documentPath,
  }) async {
    final q = HelperQualification(
      id: 'qual-${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      type: type,
      title: title,
      issuer: issuer,
      credentialId: credentialId,
      documentPath: documentPath,
      status: 'pending',
      createdAt: DateTime.now().toUtc(),
    );
    _quals.add(q);
    return q;
  }

  Future<List<UserReview>> getReviewsForUser(String userId) async {
    return List.of(_reviews.where((r) => r.revieweeId == userId));
  }

  Future<UserReview> submitReview({
    required String taskId,
    required String reviewerId,
    required String revieweeId,
    required int rating,
    String? comment,
    required bool isAboutHelper,
  }) async {
    final policy = CommunityPolicyEngine.evaluate(
      title: 'review',
      description: comment ?? '',
    );
    if (!policy.allowed) {
      throw AuthException(policy.userMessage ?? 'Review blocked by policy');
    }
    final r = UserReview(
      id: 'rev-${DateTime.now().millisecondsSinceEpoch}',
      taskId: taskId,
      reviewerId: reviewerId,
      revieweeId: revieweeId,
      rating: rating,
      comment: comment,
      isAboutHelper: isAboutHelper,
      createdAt: DateTime.now().toUtc(),
    );
    _reviews.add(r);
    return r;
  }

  Future<List<JobQuote>> getQuotesForTask(String taskId) async {
    return List.of(_quotes.where((q) => q.taskId == taskId));
  }

  Future<List<JobQuote>> getMyQuotes(String helperId) async {
    return List.of(_quotes.where((q) => q.helperId == helperId));
  }

  Future<JobQuote> submitQuote({
    required String taskId,
    required String helperId,
    required double amountLkr,
    String? message,
    double? estimatedHours,
  }) async {
    final policy = CommunityPolicyEngine.evaluate(
      title: '',
      description: message ?? '',
    );
    if (!policy.allowed) {
      throw AuthException(policy.userMessage ?? 'Quote blocked by policy');
    }
    final q = JobQuote(
      id: 'quote-${DateTime.now().millisecondsSinceEpoch}',
      taskId: taskId,
      helperId: helperId,
      amountLkr: amountLkr,
      message: message,
      estimatedHours: estimatedHours,
      createdAt: DateTime.now().toUtc(),
      helperName: 'You',
      helperRating: 4.8,
    );
    _quotes.removeWhere((e) => e.taskId == taskId && e.helperId == helperId);
    _quotes.insert(0, q);
    return q;
  }

  Future<void> respondToQuote({
    required String quoteId,
    required String status,
    required String clientId,
  }) async {
    final i = _quotes.indexWhere((q) => q.id == quoteId);
    if (i < 0) return;
    final old = _quotes[i];
    _quotes[i] = JobQuote(
      id: old.id,
      taskId: old.taskId,
      helperId: old.helperId,
      amountLkr: old.amountLkr,
      message: old.message,
      estimatedHours: old.estimatedHours,
      status: status,
      createdAt: old.createdAt,
      helperName: old.helperName,
      helperRating: old.helperRating,
    );
  }
}
