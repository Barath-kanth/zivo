import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:hyperlocal/core/errors/app_exception.dart';
import 'package:hyperlocal/data/repositories/auth_repository.dart';
import 'package:hyperlocal/data/models/user_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  ModeCubit({
    required AuthRepository authRepository,
    void Function(UserProfile profile)? onProfileUpdated,
  })  : _authRepository = authRepository,
        _onProfileUpdated = onProfileUpdated,
        super(ModeToggling());

  final AuthRepository _authRepository;
  final void Function(UserProfile profile)? _onProfileUpdated;

  /// Local UI workspace — independent of cold-start so a new browser session
  /// lands on Client, while refresh restores the last workspace.
  static const workspacePrefsKey = 'zivo_workspace_mode';
  static const workspaceHelper = 'helper';
  static const workspaceClient = 'client';

  Future<String?> _readWorkspacePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(workspacePrefsKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeWorkspacePref(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(workspacePrefsKey, value);
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> clearWorkspacePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(workspacePrefsKey);
    } catch (_) {
      /* ignore */
    }
  }

  /// Restore UI mode from local preference (default: Client on first open).
  Future<void> initFromProfile(UserProfile profile) async {
    if (profile.isGuest) {
      emit(const GuestClientMode());
      return;
    }
    final saved = await _readWorkspacePref();
    final wantHelper = saved == workspaceHelper;
    if (wantHelper && profile.canActivateHelper) {
      emit(HelperMode(profile));
    } else {
      emit(ClientMode(profile));
    }
  }

  void initGuest() {
    clearWorkspacePref();
    emit(const GuestClientMode());
  }

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

      final next = updatedProfile ??
          profile.copyWith(isHelperActive: targetIsHelper);

      await _writeWorkspacePref(
        targetIsHelper ? workspaceHelper : workspaceClient,
      );
      _onProfileUpdated?.call(next);

      if (targetIsHelper) {
        emit(HelperMode(next));
      } else {
        emit(ClientMode(next));
      }
    } on AuthException {
      emit(ClientMode(profile));
      rethrow;
    } catch (e) {
      emit(targetIsHelper ? ClientMode(profile) : HelperMode(profile));
      rethrow;
    }
  }

  /// Ensure helper workspace without flipping client→helper if already helper.
  /// Used by Active Job back navigation.
  Future<void> ensureHelperWorkspace() async {
    if (state is HelperMode) {
      await _writeWorkspacePref(workspaceHelper);
      return;
    }
    if (state is ClientMode || state is ModeHelperBlocked) {
      await toggleMode();
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
