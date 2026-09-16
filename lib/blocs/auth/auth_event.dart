import 'package:equatable/equatable.dart';
import 'package:hyperlocal/data/models/device_account.dart';
import 'package:hyperlocal/data/models/user_profile.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class AuthPhoneOtpRequested extends AuthEvent {
  const AuthPhoneOtpRequested({required this.phone});
  final String phone;
  @override
  List<Object?> get props => [phone];
}

class AuthPhoneOtpVerified extends AuthEvent {
  const AuthPhoneOtpVerified({
    required this.phone,
    required this.token,
    this.issuedCode,
  });
  final String phone;
  final String token;

  /// Code issued for this SMS (from AuthOtpSent / on-screen). Rebinds session
  /// if AuthService memory was lost (Flutter web hot reload).
  final String? issuedCode;
  @override
  List<Object?> get props => [phone, token, issuedCode];
}

class AuthRecoveryEmailLinkRequested extends AuthEvent {
  const AuthRecoveryEmailLinkRequested({required this.email});
  final String email;
  @override
  List<Object?> get props => [email];
}

class AuthSignOutRequested extends AuthEvent {}

/// Soft switch: keep this account on device, open login for another person.
class AuthAddAccountRequested extends AuthEvent {}

/// Switch to a remembered device account (demo instant; live needs OTP).
class AuthSwitchDeviceAccountRequested extends AuthEvent {
  const AuthSwitchDeviceAccountRequested(this.account);
  final DeviceAccount account;
  @override
  List<Object?> get props => [account];
}

/// Create another demo profile on this phone (for family without a handset).
class AuthCreateSharedDemoProfileRequested extends AuthEvent {
  const AuthCreateSharedDemoProfileRequested({
    required this.fullName,
    required this.phone,
  });
  final String fullName;
  final String phone;
  @override
  List<Object?> get props => [fullName, phone];
}

class AuthRemoveDeviceAccountRequested extends AuthEvent {
  const AuthRemoveDeviceAccountRequested(this.accountId);
  final String accountId;
  @override
  List<Object?> get props => [accountId];
}

/// Explicit demo only — never used as a silent fallback for auth failures.
class AuthDemoLoginRequested extends AuthEvent {}

/// After KYC onboarding submit — profile may be pending or verified.
class AuthOnboardingCompleted extends AuthEvent {
  const AuthOnboardingCompleted(this.profile);
  final UserProfile profile;
  @override
  List<Object?> get props => [profile];
}

/// Reload profile from Supabase (e.g. after ops KYC approval).
class AuthProfileRefreshRequested extends AuthEvent {}

class AuthSignInRequested extends AuthEvent {
  const AuthSignInRequested({required this.email, required this.password});
  final String email;
  final String password;
  @override
  List<Object?> get props => [email, password];
}

class AuthSignUpRequested extends AuthEvent {
  const AuthSignUpRequested({
    required this.email,
    required this.password,
    required this.fullName,
    this.username,
  });
  final String email;
  final String password;
  final String fullName;
  final String? username;
  @override
  List<Object?> get props => [email, password, fullName, username];
}

class AuthGoogleSignInRequested extends AuthEvent {}

/// OAuth redirect returned an error query (e.g. Database error saving new user).
class AuthOAuthCallbackFailed extends AuthEvent {
  const AuthOAuthCallbackFailed(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
