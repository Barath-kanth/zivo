import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'app.dart';
import 'blocs/auth/auth_bloc.dart';
import 'blocs/a11y/a11y_cubit.dart';
import 'blocs/ability/ability_cubit.dart';
import 'blocs/theme/theme_cubit.dart';
import 'core/l10n/locale_cubit.dart';
import 'blocs/mode/mode_cubit.dart';
import 'blocs/task/task_bloc.dart';
import 'blocs/wallet/wallet_bloc.dart';
import 'blocs/otp/otp_bloc.dart';
import 'core/services/auth_service.dart';
import 'core/services/gcp/gcp_api_client.dart';
import 'core/services/kyc/kyc_verifier.dart';
import 'core/services/profile_service.dart';
import 'core/utils/oauth_url.dart';
import 'core/utils/speak_text.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/profile_repository.dart';
import 'data/repositories/task_repository.dart';
import 'data/repositories/wallet_repository.dart';
import 'data/repositories/location_repository.dart';
import 'data/repositories/trust_repository.dart';
import 'data/repositories/payment_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Always publish the semantics tree on web so landmarks / roles appear for
  // screen readers and automated a11y audits (not only after Assistive Tech).
  if (kIsWeb) {
    SemanticsBinding.instance.ensureSemantics();
  }

  String? pendingOAuthError;
  if (kIsWeb) {
    usePathUrlStrategy();
    pendingOAuthError = oauthErrorFromUrl();
    sanitizeOAuthReturnUrl();
  }

  final api = GcpApiClient();
  await api.loadPersistedSession();
  final authService = AuthService(api);
  await authService.restoreSession();
  final kycVerifier = StubKycVerifier();
  final profileService = ProfileService(api, authService, kycVerifier);
  final authRepository = AuthRepository(api, authService);
  final profileRepository = ProfileRepository(profileService);
  final trustRepository = TrustRepository();
  final locationRepository = LocationRepository();
  final taskRepository = TaskRepository(api, locationRepository);
  final walletRepository = WalletRepository(api);
  final paymentRepository = PaymentRepository(api);

  // Cloud TTS for ta/si/en — browser synth is unreliable for vernacular.
  cloudSpeakOverride = (text, lang) async {
    try {
      final res = await taskRepository.cloudTts(text: text, lang: lang);
      final b64 = audioBase64FromTtsResponse(res);
      if (b64 == null) return false;
      return playCloudMp3Base64(b64);
    } catch (_) {
      return false;
    }
  };

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: api),
        RepositoryProvider.value(value: authService),
        RepositoryProvider.value(value: authRepository),
        RepositoryProvider.value(value: profileRepository),
        RepositoryProvider.value(value: trustRepository),
        RepositoryProvider.value(value: taskRepository),
        RepositoryProvider.value(value: walletRepository),
        RepositoryProvider.value(value: paymentRepository),
        RepositoryProvider.value(value: locationRepository),
        RepositoryProvider<KycVerifier>.value(value: kycVerifier),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (ctx) {
              final bloc = AuthBloc(authRepository: ctx.read<AuthRepository>())
                ..add(AuthCheckRequested());
              if (pendingOAuthError != null) {
                bloc.add(AuthOAuthCallbackFailed(pendingOAuthError));
              }
              return bloc;
            },
          ),
          BlocProvider(
            create: (ctx) => ModeCubit(
              authRepository: ctx.read<AuthRepository>(),
              onProfileUpdated: (profile) {
                ctx.read<AuthBloc>().add(AuthProfileSynced(profile));
              },
            ),
          ),
          BlocProvider(create: (_) => A11yCubit()),
          BlocProvider(create: (_) => ThemeCubit()),
          BlocProvider(
            create: (_) => AbilityCubit(
              onChanged: (p) async {
                if (!api.isSignedIn) return;
                await taskRepository.saveAbilityProfile(
                  abilities: p.abilities.toList(),
                  disclose: p.disclose,
                  note: p.note,
                );
              },
            ),
          ),
          BlocProvider(
            create: (_) {
              final locale = LocaleCubit();
              locale.onLocaleChanged = (code) async {
                if (!api.isSignedIn) return;
                if (code != 'en' && code != 'si' && code != 'ta') return;
                await taskRepository.syncPreferredLang(code);
              };
              return locale;
            },
          ),
          BlocProvider(
            create: (ctx) =>
                TaskBloc(taskRepository: ctx.read<TaskRepository>()),
          ),
          BlocProvider(
            create: (ctx) => OtpBloc(
              taskRepository: ctx.read<TaskRepository>(),
              taskBloc: ctx.read<TaskBloc>(),
            ),
          ),
          BlocProvider(
            create: (ctx) =>
                WalletBloc(walletRepository: ctx.read<WalletRepository>()),
          ),
        ],
        child: const HyperlocalApp(),
      ),
    ),
  );
}
