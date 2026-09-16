import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:hyperlocal/core/errors/app_exception.dart';
import 'package:hyperlocal/data/repositories/auth_repository.dart';
import 'package:hyperlocal/data/models/user_profile.dart';

// ── State ─────────────────────────────────────────────────────────────────────

abstract class ModeState extends Equatable {
  const ModeState();
  @override
  List<Object?> get props => [];
}

class ClientMode extends ModeState {
  const ClientMode(this.profile);
  final UserProfile profile;
  @override
  List<Object?> get props => [profile];
}

/// Not signed in — browse home only.
class GuestClientMode extends ModeState {
  const GuestClientMode();
}

class HelperMode extends ModeState {
  const HelperMode(this.profile);
  final UserProfile profile;
  @override
  List<Object?> get props => [profile];
}

class ModeToggling extends ModeState {}

/// Emitted when helper activation is blocked (e.g. KYC not verified).
class ModeHelperBlocked extends ModeState {
  const ModeHelperBlocked(this.profile, this.reason);
  final UserProfile profile;
  final String reason;
  @override
  List<Object?> get props => [profile, reason];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class ModeCubit extends Cubit<ModeState> {
  ModeCubit({required AuthRepository authRepository})
      : _authRepository = authRepository,
        super(ModeToggling());

  final AuthRepository _authRepository;

  void initFromProfile(UserProfile profile) {
    if (profile.isGuest) {
      emit(const GuestClientMode());
      return;
    }
    if (profile.isHelperActive) {
      emit(HelperMode(profile));
    } else {
      emit(ClientMode(profile));
    }
  }

  void initGuest() => emit(const GuestClientMode());

  Future<void> toggleMode() async {
    final currentState = state;
    UserProfile? profile;
    bool targetIsHelper = false;

    if (currentState is GuestClientMode) {
      return;
    }
    if (currentState is ClientMode) {
      profile = currentState.profile;
      targetIsHelper = true;
    } else if (currentState is HelperMode) {
      profile = currentState.profile;
      targetIsHelper = false;
    } else if (currentState is ModeHelperBlocked) {
      profile = currentState.profile;
      targetIsHelper = true;
    } else {
      return;
    }

    if (targetIsHelper && !profile.canActivateHelper) {
      final reason = profile.isKycPending
          ? 'Your identity is still under review. Helper mode unlocks after KYC verification.'
          : profile.kycStatus == 'rejected'
              ? 'KYC was rejected${profile.kycRejectionReason != null ? ': ${profile.kycRejectionReason}' : ''}. Resubmit documents to continue.'
              : 'Verify your NIC and complete KYC before switching to Helper mode.';
      emit(ModeHelperBlocked(profile, reason));
      emit(ClientMode(profile));
      throw AuthException(reason);
    }

    emit(ModeToggling());

    try {
      final updatedProfile = await _authRepository.toggleHelperMode(
        userId: profile.id,
        isHelperActive: targetIsHelper,
      );

      if (updatedProfile == null) {
        emit(targetIsHelper ? ClientMode(profile) : HelperMode(profile));
        return;
      }

      if (targetIsHelper) {
        emit(HelperMode(updatedProfile));
      } else {
        emit(ClientMode(updatedProfile));
      }
    } on AuthException {
      emit(ClientMode(profile));
      rethrow;
    } catch (e) {
      emit(targetIsHelper ? ClientMode(profile) : HelperMode(profile));
      rethrow;
    }
  }

  UserProfile? get currentProfile {
    if (state is ClientMode) return (state as ClientMode).profile;
    if (state is HelperMode) return (state as HelperMode).profile;
    if (state is ModeHelperBlocked) {
      return (state as ModeHelperBlocked).profile;
    }
    return null;
  }

  bool get isHelperMode => state is HelperMode;
}
