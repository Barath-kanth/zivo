import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'app.dart';
import 'blocs/auth/auth_bloc.dart';
import 'blocs/mode/mode_cubit.dart';
import 'blocs/task/task_bloc.dart';
import 'blocs/wallet/wallet_bloc.dart';
import 'blocs/otp/otp_bloc.dart';
import 'core/services/auth_service.dart';
import 'core/services/gcp/gcp_api_client.dart';
import 'core/services/kyc/kyc_verifier.dart';
import 'core/services/profile_service.dart';
import 'core/utils/oauth_url.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/profile_repository.dart';
import 'data/repositories/task_repository.dart';
import 'data/repositories/wallet_repository.dart';
import 'data/repositories/location_repository.dart';
import 'data/repositories/trust_repository.dart';
import 'data/repositories/payment_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
                bloc.add(AuthOAuthCallbackFailed(pendingOAuthError!));
              }
              return bloc;
            },
          ),
          BlocProvider(
            create: (ctx) =>
                ModeCubit(authRepository: ctx.read<AuthRepository>()),
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
