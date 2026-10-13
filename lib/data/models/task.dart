import 'package:equatable/equatable.dart';
import 'task_status.dart';

/// Lightweight lat/lng — replaces google_maps_flutter.LatLng so we don't
/// need a Maps API key just to store coordinates.
class LatLng extends Equatable {
  const LatLng(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  @override
  List<Object?> get props => [latitude, longitude];

  @override
  String toString() => 'LatLng($latitude, $longitude)';
}


enum TaskCategory {
  queueStanding,   // Stand in line at govt office, bank, hospital
  laundry,         // Wash, dry, fold, iron clothes
  groceryRun,      // Buy & bring groceries
  homeCleaning,    // Mop, sweep, dust, scrub
  homeCooking,     // Cook meals at your place
  movingHelp,      // Shift furniture, load/unload
  tutoring,        // Teach a subject or skill
  techHelp,        // Device setup, Wi-Fi, app install
  petCare,         // Walk, feed, bathe pets
  tailoring,       // Stitch, alter, hem clothes
  driver,          // Drive you in your own car
  errandRun,       // Pick up / drop off anything
  gardening,       // Water plants, weed, garden upkeep
  documentWork,    // Fill forms, photocopy, courier
  hospitalCompanion, // Accompany to doctor, hospital
  babysitting,     // Watch kids at home
  elderCare,       // Assist elderly family members
  eventHelp,       // Set up party, decoration, serve
  photography,     // Click photos/videos at events
  homeRepair,      // Fix leaks, electric, minor repairs
  other;           // Any other task not listed

  String get displayName {
    switch (this) {
      case TaskCategory.queueStanding:     return 'Queue Standing';
      case TaskCategory.laundry:           return 'Laundry';
      case TaskCategory.groceryRun:        return 'Grocery Run';
      case TaskCategory.homeCleaning:      return 'Home Cleaning';
      case TaskCategory.homeCooking:       return 'Home Cooking';
      case TaskCategory.movingHelp:        return 'Moving Help';
      case TaskCategory.tutoring:          return 'Tutoring';
      case TaskCategory.techHelp:          return 'Tech Help';
      case TaskCategory.petCare:           return 'Pet Care';
      case TaskCategory.tailoring:         return 'Tailoring';
      case TaskCategory.driver:            return 'Driver';
      case TaskCategory.errandRun:         return 'Errand Run';
      case TaskCategory.gardening:         return 'Gardening';
      case TaskCategory.documentWork:      return 'Document Help';
      case TaskCategory.hospitalCompanion: return 'Hospital Aid';
      case TaskCategory.babysitting:       return 'Babysitting';
      case TaskCategory.elderCare:         return 'Elder Care';
      case TaskCategory.eventHelp:         return 'Event Help';
      case TaskCategory.photography:       return 'Photography';
      case TaskCategory.homeRepair:        return 'Home Repair';
      case TaskCategory.other:             return 'Other';
    }
  }

  String get emoji {
    switch (this) {
      case TaskCategory.queueStanding:     return '🚶';
      case TaskCategory.laundry:           return '👕';
      case TaskCategory.groceryRun:        return '🛒';
      case TaskCategory.homeCleaning:      return '🧹';
      case TaskCategory.homeCooking:       return '🍳';
      case TaskCategory.movingHelp:        return '📦';
      case TaskCategory.tutoring:          return '📚';
      case TaskCategory.techHelp:          return '💻';
      case TaskCategory.petCare:           return '🐕';
      case TaskCategory.tailoring:         return '✂️';
      case TaskCategory.driver:            return '🚗';
      case TaskCategory.errandRun:         return '🛵';
      case TaskCategory.gardening:         return '🌿';
      case TaskCategory.documentWork:      return '📝';
      case TaskCategory.hospitalCompanion: return '🏥';
      case TaskCategory.babysitting:       return '👶';
      case TaskCategory.elderCare:         return '🧓';
      case TaskCategory.eventHelp:         return '🎉';
      case TaskCategory.photography:       return '📷';
      case TaskCategory.homeRepair:        return '🔧';
      case TaskCategory.other:             return '📌';
    }
  }

  String get description {
    switch (this) {
      case TaskCategory.queueStanding:     return 'Stand in line at govt office, bank or hospital for you';
      case TaskCategory.laundry:           return 'Wash, dry, fold and iron your clothes at home';
      case TaskCategory.groceryRun:        return 'Buy groceries from the market and deliver home';
      case TaskCategory.homeCleaning:      return 'Sweep, mop, dust and scrub your home clean';
      case TaskCategory.homeCooking:       return 'Cook fresh meals at your home or for your family';
      case TaskCategory.movingHelp:        return 'Help shift furniture, pack and unload boxes';
      case TaskCategory.tutoring:          return 'Teach a subject, skill or language in person';
      case TaskCategory.techHelp:          return 'Set up devices, fix Wi-Fi, install apps';
      case TaskCategory.petCare:           return 'Walk, feed, bathe or look after your pet';
      case TaskCategory.tailoring:         return 'Stitch, alter, hem or repair your clothes';
      case TaskCategory.driver:            return 'Drive you around in your own car';
      case TaskCategory.errandRun:         return 'Pick up or drop off anything across the city';
      case TaskCategory.gardening:         return 'Water plants, remove weeds and tend your garden';
      case TaskCategory.documentWork:      return 'Fill forms, make photocopies, visit courier office';
      case TaskCategory.hospitalCompanion: return 'Accompany to doctor, hospital or pharmacy';
      case TaskCategory.babysitting:       return 'Watch and care for your children at home';
      case TaskCategory.elderCare:         return 'Assist elderly family members with daily needs';
      case TaskCategory.eventHelp:         return 'Set up, decorate and assist at your event or party';
      case TaskCategory.photography:       return 'Click photos or record videos at your event';
      case TaskCategory.homeRepair:        return 'Fix leaks, minor electrical, painting and repairs';
      case TaskCategory.other:             return 'Any other help you might need';
    }
  }

  static TaskCategory fromString(String value) {
    return TaskCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TaskCategory.errandRun,
    );
  }
}

class Task extends Equatable {
  const Task({
    required this.id,
    required this.clientId,
    this.helperId,
    required this.title,
    required this.description,
    required this.category,
    required this.estimatedHours,
    required this.hourlyRate,
    required this.totalAmount,
    required this.location,
    this.locationAddress,
    this.locationLabel,
    required this.status,
    this.startOtp,
    this.endOtp,
    this.startOtpVerifiedAt,
    this.endOtpVerifiedAt,
    this.scheduledAt,
    this.matchedAt,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
    // For helper feed only
    this.distanceKm,
    this.clientProfile,
    this.goodsBudget = 0,
    this.goodsSpent = 0,
    this.requiresPurchaseProof = false,
    this.requiresCompletionProof = true,
    this.completionChecklist = const [],
    this.proofSubmittedAt,
    this.proofPhotoUrls = const [],
    this.proofCheckedItems = const [],
    this.proofNote,
    this.clientConfirmedDeliveryAt,
    this.disputedAt,
    this.disputeReason,
    this.storeName,
    this.photoUrls = const [],
    this.photoPaths = const [],
    this.matchExplanation,
    this.matchReasons = const [],
    this.matchMode,
    this.helperProfile,
    this.bundleId,
    this.bundleTitle,
    this.bookedForUserId,
    this.bookedForName,
    this.shareToken,
  });

  final String id;
  final String clientId;
  final String? helperId;
  final String title;
  final String description;
  final TaskCategory category;
  final double estimatedHours;
  final double hourlyRate;
  final double totalAmount;
  final LatLng location;
  final String? locationAddress;
  final String? locationLabel;
  final TaskStatus status;
  final String? startOtp;
  final String? endOtp;
  final DateTime? startOtpVerifiedAt;
  final DateTime? endOtpVerifiedAt;
  final DateTime? scheduledAt;
  final DateTime? matchedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  // Denormalized for UI display
  final double? distanceKm;
  final Map<String, dynamic>? clientProfile;

  /// Max grocery spend held in escrow (never cash to helper).
  final double goodsBudget;
  final double goodsSpent;
  final bool requiresPurchaseProof;
  final bool requiresCompletionProof;
  final List<String> completionChecklist;
  final DateTime? proofSubmittedAt;
  final List<String> proofPhotoUrls;
  final List<String> proofCheckedItems;
  final String? proofNote;
  final DateTime? clientConfirmedDeliveryAt;
  final DateTime? disputedAt;
  final String? disputeReason;
  final String? storeName;

  /// Reference photos attached at create time (all categories).
  final List<String> photoUrls;
  /// GCS object paths (used to refresh signed URLs for helpers).
  final List<String> photoPaths;

  /// Client-facing "Explain my match" copy from Pillar C / Instant Dispatch.
  final String? matchExplanation;
  final List<String> matchReasons;
  final String? matchMode;
  /// Nested helper snapshot from API (`helper.full_name`, rating, …).
  final Map<String, dynamic>? helperProfile;

  /// One problem → several tasks.
  final String? bundleId;
  final String? bundleTitle;

  /// Family Assist — booked on behalf of someone else.
  final String? bookedForUserId;
  final String? bookedForName;

  /// Shared live token for family watchers.
  final String? shareToken;

  String? get helperDisplayName =>
      helperProfile?['full_name'] as String? ??
      helperProfile?['name'] as String?;

  bool get isPurchaseTask =>
      category == TaskCategory.groceryRun ||
      category == TaskCategory.errandRun ||
      requiresPurchaseProof;

  bool get needsCompletionProof =>
      requiresCompletionProof || requiresPurchaseProof;

  bool get hasCompletionProof => proofSubmittedAt != null;

  double get escrowTotal => totalAmount + goodsBudget;

  factory Task.fromJson(Map<String, dynamic> json) {
    // PostGIS returns geography as GeoJSON or WKT; Supabase REST returns
    // geography columns as {"type": "Point", "coordinates": [lon, lat]}
    LatLng _parseLocation(dynamic loc) {
      if (loc is Map) {
        final coords = loc['coordinates'] as List;
        return LatLng(
          (coords[1] as num).toDouble(),
          (coords[0] as num).toDouble(),
        );
      }
      final lat = json['lat'] ?? json['latitude'];
      final lon = json['lon'] ?? json['lng'] ?? json['longitude'];
      if (lat is num && lon is num) {
        return LatLng(lat.toDouble(), lon.toDouble());
      }
      return const LatLng(0, 0);
    }

    return Task(
      id:                   json['id'] as String,
      clientId:             json['client_id'] as String,
      helperId:             json['helper_id'] as String?,
      title:                json['title'] as String,
      description:          json['description'] as String? ?? '',
      category:             TaskCategory.fromString(json['category'] as String),
      estimatedHours:       (json['estimated_hours'] as num?)?.toDouble() ?? 1,
      hourlyRate:           (json['hourly_rate'] as num?)?.toDouble() ?? 0,
      totalAmount:          (json['total_amount'] as num?)?.toDouble() ??
                            ((json['estimated_hours'] as num?)?.toDouble() ?? 1) *
                            ((json['hourly_rate'] as num?)?.toDouble() ?? 0),
      location:             _parseLocation(json['location']),
      locationAddress:      json['location_address'] as String?,
      locationLabel:        json['location_label'] as String?,
      status:               TaskStatus.fromString(json['status'] as String),
      startOtp:             json['start_otp'] as String?,
      endOtp:               json['end_otp'] as String?,
      startOtpVerifiedAt:   json['start_otp_verified_at'] != null
                              ? DateTime.parse(json['start_otp_verified_at'])
                              : null,
      endOtpVerifiedAt:     json['end_otp_verified_at'] != null
                              ? DateTime.parse(json['end_otp_verified_at'])
                              : null,
      scheduledAt:          json['scheduled_at'] != null
                              ? DateTime.parse(json['scheduled_at'])
                              : null,
      matchedAt:            json['matched_at'] != null
                              ? DateTime.parse(json['matched_at'])
                              : null,
      startedAt:            json['started_at'] != null
                              ? DateTime.parse(json['started_at'])
                              : null,
      completedAt:          json['completed_at'] != null
                              ? DateTime.parse(json['completed_at'])
                              : null,
      createdAt:            DateTime.parse(json['created_at'] as String),
      distanceKm:           (json['distance_km'] as num?)?.toDouble(),
      clientProfile:        json['client_profile'] as Map<String, dynamic>?,
      goodsBudget:          (json['goods_budget'] as num?)?.toDouble() ?? 0,
      goodsSpent:           (json['goods_spent'] as num?)?.toDouble() ?? 0,
      requiresPurchaseProof: json['requires_purchase_proof'] as bool? ?? false,
      requiresCompletionProof:
          json['requires_completion_proof'] as bool? ?? true,
      completionChecklist: (json['completion_checklist'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      proofSubmittedAt:     json['proof_submitted_at'] != null
                              ? DateTime.tryParse(json['proof_submitted_at'] as String)
                              : null,
      proofPhotoUrls: (json['proof_photo_urls'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      proofCheckedItems: (json['proof_checked_items'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      proofNote: json['proof_note'] as String?,
      clientConfirmedDeliveryAt: json['client_confirmed_delivery_at'] != null
                              ? DateTime.tryParse(
                                  json['client_confirmed_delivery_at'] as String)
                              : null,
      disputedAt:           json['disputed_at'] != null
                              ? DateTime.tryParse(json['disputed_at'] as String)
                              : null,
      disputeReason:        json['dispute_reason'] as String?,
      storeName:            json['store_name'] as String?,
      photoUrls:            (json['photo_urls'] as List?)
                              ?.map((e) => e.toString())
                              .toList() ??
                          const [],
      photoPaths:           (json['photo_paths'] as List?)
                              ?.map((e) => e.toString())
                              .toList() ??
                          const [],
      matchExplanation:     json['match_explanation'] as String?,
      matchReasons:         (json['match_reasons'] as List?)
                              ?.map((e) => e.toString())
                              .toList() ??
                          const [],
      matchMode:            json['match_mode'] as String?,
      helperProfile:        json['helper'] is Map
          ? Map<String, dynamic>.from(json['helper'] as Map)
          : null,
      bundleId:             json['bundle_id'] as String?,
      bundleTitle:          json['bundle_title'] as String?,
      bookedForUserId:      json['booked_for_user_id'] as String?,
      bookedForName:        json['booked_for_name'] as String?,
      shareToken:           json['share_token'] as String?,
    );
  }

  Map<String, dynamic> toInsertJson({
    required double lat,
    required double lon,
  }) => {
    'client_id':      clientId,
    'title':          title,
    'description':    description,
    'category':       category.name,
    'estimated_hours': estimatedHours,
    'hourly_rate':    hourlyRate,
    'location':       'POINT($lon $lat)',  // WKT format for PostGIS insert
    'location_address': locationAddress,
    'location_label': locationLabel,
  };

  /// Wire format for feed refresh / Task.fromJson.
  Map<String, dynamic> toJson() => {
    'id': id,
    'client_id': clientId,
    'helper_id': helperId,
    'title': title,
    'description': description,
    'category': category.name,
    'estimated_hours': estimatedHours,
    'hourly_rate': hourlyRate,
    'total_amount': totalAmount,
    'lat': location.latitude,
    'lon': location.longitude,
    'location_address': locationAddress,
    'location_label': locationLabel,
    'status': status.dbValue,
    'start_otp': startOtp,
    'end_otp': endOtp,
    'created_at': createdAt.toIso8601String(),
    'distance_km': distanceKm,
    'goods_budget': goodsBudget,
    'goods_spent': goodsSpent,
    'requires_purchase_proof': requiresPurchaseProof,
    'requires_completion_proof': requiresCompletionProof,
    'completion_checklist': completionChecklist,
    'proof_submitted_at': proofSubmittedAt?.toIso8601String(),
    'proof_photo_urls': proofPhotoUrls,
    'proof_checked_items': proofCheckedItems,
    'proof_note': proofNote,
    'photo_urls': photoUrls,
    'photo_paths': photoPaths,
    'match_explanation': matchExplanation,
    'match_reasons': matchReasons,
    'match_mode': matchMode,
    if (helperProfile != null) 'helper': helperProfile,
    'bundle_id': bundleId,
    'bundle_title': bundleTitle,
    'booked_for_user_id': bookedForUserId,
    'booked_for_name': bookedForName,
    'share_token': shareToken,
  };

  Task copyWith({
    String? helperId,
    TaskStatus? status,
    String? startOtp,
    String? endOtp,
    DateTime? startOtpVerifiedAt,
    DateTime? endOtpVerifiedAt,
    DateTime? matchedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    double? goodsBudget,
    double? goodsSpent,
    bool? requiresPurchaseProof,
    bool? requiresCompletionProof,
    List<String>? completionChecklist,
    DateTime? proofSubmittedAt,
    List<String>? proofPhotoUrls,
    List<String>? proofCheckedItems,
    String? proofNote,
    DateTime? clientConfirmedDeliveryAt,
    String? disputeReason,
    List<String>? photoUrls,
    List<String>? photoPaths,
    String? matchExplanation,
    List<String>? matchReasons,
    String? matchMode,
    Map<String, dynamic>? helperProfile,
  }) {
    return Task(
      id: id,
      clientId: clientId,
      helperId: helperId ?? this.helperId,
      title: title,
      description: description,
      category: category,
      estimatedHours: estimatedHours,
      hourlyRate: hourlyRate,
      totalAmount: totalAmount,
      location: location,
      locationAddress: locationAddress,
      locationLabel: locationLabel,
      status: status ?? this.status,
      startOtp: startOtp ?? this.startOtp,
      endOtp: endOtp ?? this.endOtp,
      startOtpVerifiedAt: startOtpVerifiedAt ?? this.startOtpVerifiedAt,
      endOtpVerifiedAt: endOtpVerifiedAt ?? this.endOtpVerifiedAt,
      scheduledAt: scheduledAt,
      matchedAt: matchedAt ?? this.matchedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt,
      distanceKm: distanceKm,
      clientProfile: clientProfile,
      goodsBudget: goodsBudget ?? this.goodsBudget,
      goodsSpent: goodsSpent ?? this.goodsSpent,
      requiresPurchaseProof:
          requiresPurchaseProof ?? this.requiresPurchaseProof,
      requiresCompletionProof:
          requiresCompletionProof ?? this.requiresCompletionProof,
      completionChecklist: completionChecklist ?? this.completionChecklist,
      proofSubmittedAt: proofSubmittedAt ?? this.proofSubmittedAt,
      proofPhotoUrls: proofPhotoUrls ?? this.proofPhotoUrls,
      proofCheckedItems: proofCheckedItems ?? this.proofCheckedItems,
      proofNote: proofNote ?? this.proofNote,
      clientConfirmedDeliveryAt:
          clientConfirmedDeliveryAt ?? this.clientConfirmedDeliveryAt,
      disputedAt: disputedAt,
      disputeReason: disputeReason ?? this.disputeReason,
      storeName: storeName,
      photoUrls: photoUrls ?? this.photoUrls,
      photoPaths: photoPaths ?? this.photoPaths,
      matchExplanation: matchExplanation ?? this.matchExplanation,
      matchReasons: matchReasons ?? this.matchReasons,
      matchMode: matchMode ?? this.matchMode,
      helperProfile: helperProfile ?? this.helperProfile,
      bundleId: bundleId,
      bundleTitle: bundleTitle,
      bookedForUserId: bookedForUserId,
      bookedForName: bookedForName,
      shareToken: shareToken,
    );
  }

  @override
  List<Object?> get props => [
    id, clientId, helperId, title, status,
    startOtp, endOtp, startedAt, completedAt,
  ];
}
