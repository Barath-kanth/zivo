import 'package:equatable/equatable.dart';

class UserReview extends Equatable {
  const UserReview({
    required this.id,
    required this.taskId,
    required this.reviewerId,
    required this.revieweeId,
    required this.rating,
    this.comment,
    required this.isAboutHelper,
    required this.createdAt,
    this.reviewerName,
  });

  final String id;
  final String taskId;
  final String reviewerId;
  final String revieweeId;
  final int rating;
  final String? comment;
  final bool isAboutHelper;
  final DateTime createdAt;
  final String? reviewerName;

  factory UserReview.fromJson(Map<String, dynamic> json) {
    final reviewer = json['reviewer'];
    String? name;
    if (reviewer is Map) {
      name = reviewer['full_name'] as String?;
    }
    return UserReview(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      reviewerId: json['reviewer_id'] as String,
      revieweeId: json['reviewee_id'] as String,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String?,
      isAboutHelper: json['is_about_helper'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      reviewerName: name,
    );
  }

  @override
  List<Object?> get props => [id, rating, revieweeId];
}

class JobQuote extends Equatable {
  const JobQuote({
    required this.id,
    required this.taskId,
    required this.helperId,
    required this.amountLkr,
    this.message,
    this.estimatedHours,
    this.status = 'open',
    required this.createdAt,
    this.helperName,
    this.helperRating,
  });

  final String id;
  final String taskId;
  final String helperId;
  final double amountLkr;
  final String? message;
  final double? estimatedHours;
  final String status;
  final DateTime createdAt;
  final String? helperName;
  final double? helperRating;

  factory JobQuote.fromJson(Map<String, dynamic> json) {
    final helper = json['helper'];
    String? name;
    double? rating;
    if (helper is Map) {
      name = helper['full_name'] as String?;
      rating = (helper['rating_as_helper'] as num?)?.toDouble();
    }
    return JobQuote(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      helperId: json['helper_id'] as String,
      amountLkr: (json['amount_lkr'] as num?)?.toDouble() ?? 0,
      message: json['message'] as String?,
      estimatedHours: (json['estimated_hours'] as num?)?.toDouble(),
      status: json['status'] as String? ?? 'open',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      helperName: name,
      helperRating: rating,
    );
  }

  @override
  List<Object?> get props => [id, taskId, helperId, amountLkr, status];
}
