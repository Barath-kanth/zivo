import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:hyperlocal/data/models/user_profile.dart';

/// An account remembered on this device (shared-phone / multi-profile).
class DeviceAccount extends Equatable {
  const DeviceAccount({
    required this.id,
    required this.phone,
    required this.fullName,
    this.avatarUrl,
    this.isDemo = false,
    this.profileJson,
    required this.lastUsedAt,
  });

  final String id;
  final String phone;
  final String fullName;
  final String? avatarUrl;
  final bool isDemo;

  /// Full profile snapshot for demo / offline switch (JSON map).
  final Map<String, dynamic>? profileJson;
  final DateTime lastUsedAt;

  String get initial =>
      fullName.trim().isNotEmpty ? fullName.trim()[0].toUpperCase() : '?';

  UserProfile? get demoProfile {
    if (!isDemo || profileJson == null) return null;
    try {
      return UserProfile.fromJson(profileJson!);
    } catch (_) {
      return null;
    }
  }

  factory DeviceAccount.fromProfile(UserProfile p, {required bool isDemo}) {
    return DeviceAccount(
      id: p.id,
      phone: p.phone ?? '',
      fullName: p.fullName.isEmpty ? 'Profile' : p.fullName,
      avatarUrl: p.avatarUrl,
      isDemo: isDemo,
      profileJson: isDemo ? p.toJson() : null,
      lastUsedAt: DateTime.now(),
    );
  }

  DeviceAccount copyWith({
    String? fullName,
    String? avatarUrl,
    Map<String, dynamic>? profileJson,
    DateTime? lastUsedAt,
  }) {
    return DeviceAccount(
      id: id,
      phone: phone,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isDemo: isDemo,
      profileJson: profileJson ?? this.profileJson,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'full_name': fullName,
        'avatar_url': avatarUrl,
        'is_demo': isDemo,
        'profile_json': profileJson,
        'last_used_at': lastUsedAt.toIso8601String(),
      };

  factory DeviceAccount.fromJson(Map<String, dynamic> json) {
    final rawProfile = json['profile_json'];
    return DeviceAccount(
      id: json['id'] as String,
      phone: json['phone'] as String? ?? '',
      fullName: json['full_name'] as String? ?? 'Profile',
      avatarUrl: json['avatar_url'] as String?,
      isDemo: json['is_demo'] as bool? ?? false,
      profileJson: rawProfile is Map<String, dynamic>
          ? rawProfile
          : rawProfile is String
              ? (jsonDecode(rawProfile) as Map<String, dynamic>?)
              : null,
      lastUsedAt: DateTime.tryParse(json['last_used_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props =>
      [id, phone, fullName, avatarUrl, isDemo, lastUsedAt];
}
