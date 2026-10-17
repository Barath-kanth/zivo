import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/services/auth_service.dart';
import 'package:hyperlocal/core/services/device_account_store.dart';
import 'package:hyperlocal/core/utils/phone_utils.dart';
import 'package:hyperlocal/data/models/user_profile.dart';
import 'package:hyperlocal/data/repositories/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyperlocal/core/errors/app_exception.dart';
import 'auth_event.dart';
import 'auth_state.dart';

export 'auth_event.dart';
export 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required AuthRepository authRepository})
      : _authRepository = authRepository,
        super(AuthLoading()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthPhoneOtpRequested>(_onPhoneOtpRequested);
    on<AuthPhoneOtpVerified>(_onPhoneOtpVerified);
    on<AuthRecoveryEmailLinkRequested>(_onRecoveryEmail);
    on<AuthSignOutRequested>(_onSignOutRequested);
    on<AuthAddAccountRequested>(_onAddAccount);
    on<AuthSwitchDeviceAccountRequested>(_onSwitchDeviceAccount);
    on<AuthCreateSharedDemoProfileRequested>(_onCreateSharedDemo);
    on<AuthRemoveDeviceAccountRequested>(_onRemoveDeviceAccount);
    on<AuthDemoLoginRequested>(_onDemoLogin);
    on<AuthOnboardingCompleted>(_onOnboardingCompleted);
    on<AuthProfileSynced>(_onProfileSynced);
    on<AuthProfileRefreshRequested>(_onProfileRefresh);
    on<AuthSignInRequested>(_onSignIn);
    on<AuthSignUpRequested>(_onSignUp);
    on<AuthGoogleSignInRequested>(_onGoogleSignIn);
    on<AuthOAuthCallbackFailed>(_onOAuthCallbackFailed);
  }

  final AuthRepository _authRepository;
  int _otpAttempts = 0;

  /// Last free-OTP issued for this login attempt (survives AuthLoading).
  String? _issuedOtpPhone;
  String? _issuedOtpCode;

  Future<void> _remember(UserProfile profile, {required bool isDemo}) async {
    await DeviceAccountStore.upsertFromProfile(profile, isDemo: isDemo);
  }

  /// Browse-first: signed-in users enter Client mode immediately.
  /// KYC is gated later for Helper mode (see [UserProfile.needsKycForHelper]).
  void _emitFromProfile(Emitter<AuthState> emit, UserProfile profile) {
    emit(AuthAuthenticated(profile));
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      // Prefer live Supabase session over any leftover demo cache.
      final profile = await _authRepository.getCurrentProfile();
      if (profile != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('demo_login_time');
        await _remember(profile, isDemo: false);
        _emitFromProfile(emit, profile);
        return;
      }

      final session = _authRepository.authService.currentSession;
      if (session != null) {
        final ensured = await _authRepository.ensureProfile();
        if (ensured != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('demo_login_time');
          await _remember(ensured, isDemo: false);
          _emitFromProfile(emit, ensured);
          return;
        }
      }

      if (AppConfig.demoAllowed) {
        final prefs = await SharedPreferences.getInstance();
        final lastLogin = prefs.getInt('demo_login_time') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastLogin < 600000) {
          final activeId = await DeviceAccountStore.activeId();
          if (activeId != null) {
            final accounts = await DeviceAccountStore.list();
            final match = accounts.where((a) => a.id == activeId);
            if (match.isNotEmpty && match.first.demoProfile != null) {
              final p = match.first.demoProfile!;
              await _remember(p, isDemo: true);
              emit(AuthAuthenticated(p));
              return;
            }
          }
        }
      }

      emit(AuthUnauthenticated());
    } catch (_) {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onPhoneOtpRequested(
    AuthPhoneOtpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final e164 = PhoneUtils.toE164(event.phone);
      if (e164 == null) {
        emit(const AuthFailure('Enter a valid Sri Lanka mobile (+94).'));
        return;
      }
      await _authRepository.requestPhoneOtp(e164);
      _otpAttempts = 0;
      final svc = _authRepository.authService;
      _issuedOtpPhone = e164;
      _issuedOtpCode = svc.peekIssuedOtpCode(e164) ?? svc.lastFreeOtpCode;
      emit(AuthOtpSent(
        phone: e164,
        resendAvailableAt: DateTime.now().add(
          const Duration(seconds: AuthService.otpResendCooldownSeconds),
        ),
        freeDevOtpCode: _issuedOtpCode,
        deliveryWarning: svc.lastOtpDeliveryWarning,
        viaTextBee: false,
      ));
    } on AuthException catch (e) {
      emit(AuthFailure(e.message, phone: event.phone));
    } catch (e) {
      emit(AuthFailure(
        'Could not send OTP. Is the GCP API running? ($e)',
        phone: event.phone,
      ));
    }
  }

  Future<void> _onPhoneOtpVerified(
    AuthPhoneOtpVerified event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    if (_otpAttempts >= AuthService.maxClientOtpAttempts) {
      emit(AuthFailure(
        'Too many attempts. Request a new code.',
        phone: event.phone,
      ));
      return;
    }
    _otpAttempts++;
    try {
      final profile = await _authRepository.verifyPhoneOtp(
        phone: event.phone,
        token: event.token,
        issuedCode: event.issuedCode ??
            (_issuedOtpPhone != null &&
                    PhoneUtils.toE164(event.phone) == _issuedOtpPhone
                ? _issuedOtpCode
                : null),
      );
      if (profile == null) {
        emit(AuthFailure(
          'Verification failed. Try again.',
          phone: event.phone,
        ));
        return;
      }
      _otpAttempts = 0;
      _issuedOtpCode = null;
      _issuedOtpPhone = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('demo_login_time');
      await _remember(profile, isDemo: false);
      _emitFromProfile(emit, profile);
    } on AuthException catch (e) {
      emit(AuthFailure(e.message, phone: event.phone));
    } catch (e) {
      emit(AuthFailure(
        e.toString().replaceFirst('Exception: ', ''),
        phone: event.phone,
      ));
    }
  }

  Future<void> _onRecoveryEmail(
    AuthRecoveryEmailLinkRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await _authRepository.sendRecoveryEmail(event.email);
      emit(AuthRecoveryEmailSent(event.email));
    } on AuthException catch (e) {
      emit(AuthFailure(e.message));
    } catch (_) {
      emit(const AuthFailure('Could not send recovery email.'));
    }
  }

  Future<void> _onSignOutRequested(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('demo_login_time');
    await DeviceAccountStore.clearPendingSwitch();
    await _authRepository.signOut();
    emit(AuthUnauthenticated());
  }

  Future<void> _onAddAccount(
    AuthAddAccountRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (state is AuthAuthenticated) {
      final prefs = await SharedPreferences.getInstance();
      final isDemo = prefs.getInt('demo_login_time') != null;
      await _remember((state as AuthAuthenticated).profile, isDemo: isDemo);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('demo_login_time');
    await DeviceAccountStore.setAddingAccount();
    await _authRepository.signOut();
    emit(AuthUnauthenticated());
  }

  Future<void> _onSwitchDeviceAccount(
    AuthSwitchDeviceAccountRequested event,
    Emitter<AuthState> emit,
  ) async {
    final account = event.account;
    if (state is AuthAuthenticated &&
        (state as AuthAuthenticated).profile.id == account.id) {
      return;
    }

    if (state is AuthAuthenticated) {
      final prefs = await SharedPreferences.getInstance();
      final isDemo = prefs.getInt('demo_login_time') != null;
      await _remember((state as AuthAuthenticated).profile, isDemo: isDemo);
    }

    if (account.isDemo && account.demoProfile != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'demo_login_time',
        DateTime.now().millisecondsSinceEpoch,
      );
      await _authRepository.signOut();
      await _remember(account.demoProfile!, isDemo: true);
      emit(AuthAuthenticated(account.demoProfile!));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('demo_login_time');
    await DeviceAccountStore.setAddingAccount(prefillPhone: account.phone);
    await _authRepository.signOut();
    emit(AuthUnauthenticated());
  }

  Future<void> _onCreateSharedDemo(
    AuthCreateSharedDemoProfileRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthFailure('Demo profiles are disabled. Use phone OTP.'));
  }

  Future<void> _onRemoveDeviceAccount(
    AuthRemoveDeviceAccountRequested event,
    Emitter<AuthState> emit,
  ) async {
    await DeviceAccountStore.remove(event.accountId);
    if (state is AuthAuthenticated) {
      emit(AuthAuthenticated((state as AuthAuthenticated).profile));
    }
  }

  Future<void> _onDemoLogin(
    AuthDemoLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthFailure(
      'Demo mode is disabled. Sign in with phone OTP.',
    ));
  }

  Future<void> _onProfileRefresh(
    AuthProfileRefreshRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      final profile = await _authRepository.getCurrentProfile();
      if (profile == null) return;
      await _remember(profile, isDemo: false);
      _emitFromProfile(emit, profile);
    } catch (_) {}
  }

  Future<void> _onOnboardingCompleted(
    AuthOnboardingCompleted event,
    Emitter<AuthState> emit,
  ) async {
    await _remember(event.profile, isDemo: false);
    // Always leave onboarding after a successful KYC submit (pending or verified).
    emit(AuthAuthenticated(event.profile));
  }

  Future<void> _onProfileSynced(
    AuthProfileSynced event,
    Emitter<AuthState> emit,
  ) async {
    await _remember(event.profile, isDemo: false);
    emit(AuthAuthenticated(event.profile));
  }

  Future<void> _onSignIn(
    AuthSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('demo_login_time');
      final profile = await _authRepository.signInWithEmailPassword(
        email: event.email,
        password: event.password,
      );
      if (profile == null) {
        emit(const AuthFailure('Sign in failed. Check your email and password.'));
        return;
      }
      await _remember(profile, isDemo: false);
      _emitFromProfile(emit, profile);
    } on AuthException catch (e) {
      emit(AuthFailure(e.message));
    } catch (e) {
      emit(AuthFailure(e.toString().replaceFirst('Exception: ', '')));
    }
  }

  Future<void> _onSignUp(
    AuthSignUpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('demo_login_time');
      final profile = await _authRepository.signUpWithEmailPassword(
        email: event.email,
        password: event.password,
        fullName: event.fullName,
        username: event.username,
      );
      if (profile == null) {
        emit(const AuthFailure('Could not create account. Try again.'));
        return;
      }
      await _remember(profile, isDemo: false);
      _emitFromProfile(emit, profile);
    } on AuthException catch (e) {
      emit(AuthFailure(e.message));
    } catch (e) {
      emit(AuthFailure(e.toString().replaceFirst('Exception: ', '')));
    }
  }

  Future<void> _onGoogleSignIn(
    AuthGoogleSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('demo_login_time');
      final profile = await _authRepository.signInWithGoogle();
      if (profile == null) {
        // Web OAuth redirect in progress — keep loading briefly; page will reload.
        emit(AuthLoading());
        return;
      }
      await _remember(profile, isDemo: false);
      _emitFromProfile(emit, profile);
    } on AuthException catch (e) {
      emit(AuthFailure(e.message));
    } catch (e) {
      emit(AuthFailure(e.toString().replaceFirst('Exception: ', '')));
    }
  }

  Future<void> _onOAuthCallbackFailed(
    AuthOAuthCallbackFailed event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthFailure(
      event.message.contains('Database error')
          ? 'Google sign-in failed: profile could not be created. '
              'Google Sign-In is not wired for the GCP Cup build yet. Use phone OTP or email/password.'
          : event.message,
    ));
  }
}
