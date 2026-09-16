import 'package:equatable/equatable.dart';
import 'package:hyperlocal/data/models/user_profile.dart';

abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.profile);
  final UserProfile profile;
  @override
  List<Object?> get props => [profile];
}

/// User signed in but hasn't completed KYC / profile onboarding.
class AuthNeedsOnboarding extends AuthState {
  const AuthNeedsOnboarding(this.userId, {this.profile});
  final String userId;
  final UserProfile? profile;
  @override
  List<Object?> get props => [userId, profile];
}

/// OTP SMS sent — waiting for user to enter code.
class AuthOtpSent extends AuthState {
  const AuthOtpSent({
    required this.phone,
    required this.resendAvailableAt,
    this.freeDevOtpCode,
    this.deliveryWarning,
    this.viaTextBee = false,
  });
  final String phone;
  final DateTime resendAvailableAt;

  /// When SMS provider is missing, free in-app OTP is shown here.
  final String? freeDevOtpCode;

  /// e.g. TextBee device not registered — OTP still usable on-screen.
  final String? deliveryWarning;

  final bool viaTextBee;

  @override
  List<Object?> get props =>
      [phone, resendAvailableAt, freeDevOtpCode, deliveryWarning, viaTextBee];
}

class AuthUnauthenticated extends AuthState {}

class AuthFailure extends AuthState {
  const AuthFailure(this.message, {this.phone});
  final String message;
  final String? phone;
  @override
  List<Object?> get props => [message, phone];
}

class AuthRecoveryEmailSent extends AuthState {
  const AuthRecoveryEmailSent(this.email);
  final String email;
  @override
  List<Object?> get props => [email];
}
