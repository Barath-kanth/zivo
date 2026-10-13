import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/core/constants/app_brand.dart';
import 'package:hyperlocal/core/constants/app_theme.dart';
import 'package:hyperlocal/core/services/auth_service.dart';
import 'package:hyperlocal/core/services/gcp/gcp_api_client.dart';
import 'package:hyperlocal/core/services/kyc/kyc_verifier.dart';
import 'package:hyperlocal/core/services/profile_service.dart';
import 'package:hyperlocal/data/repositories/auth_repository.dart';
import 'package:hyperlocal/data/repositories/profile_repository.dart';
import 'package:hyperlocal/ui/admin/admin_dashboard_screen.dart';
import 'package:hyperlocal/ui/auth/login_screen.dart';

/// Optional Admin process — prefer main app `/admin`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) usePathUrlStrategy();

  final api = GcpApiClient();
  await api.loadPersistedSession();
  final authService = AuthService(api);
  await authService.restoreSession();
  final profileService = ProfileService(api, authService, StubKycVerifier());
  final authRepository = AuthRepository(api, authService);
  final profileRepository = ProfileRepository(profileService);

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: api),
        RepositoryProvider.value(value: authRepository),
        RepositoryProvider.value(value: profileRepository),
        RepositoryProvider.value(value: authService),
      ],
      child: BlocProvider(
        create: (_) => AuthBloc(authRepository: authRepository)
          ..add(AuthCheckRequested()),
        child: const ZivoAdminApp(),
      ),
    ),
  );
}

class ZivoAdminApp extends StatelessWidget {
  const ZivoAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authBloc = context.read<AuthBloc>();
    final refresh = _AdminAuthRefresh(authBloc.stream);
    final router = GoRouter(
      initialLocation: '/admin',
      refreshListenable: refresh,
      redirect: (ctx, state) {
        final auth = authBloc.state;
        final loc = state.uri.path;
        final loggedIn = auth is AuthAuthenticated;
        if (loc == '/' || loc.isEmpty) {
          return loggedIn ? '/admin' : '/login?returnTo=%2Fadmin';
        }
        if (!loggedIn && loc != '/login') {
          return '/login?returnTo=%2Fadmin';
        }
        if (loggedIn && loc == '/login') return '/admin';
        return null;
      },
      routes: [
        GoRoute(path: '/', redirect: (_, __) => '/admin'),
        GoRoute(
          path: '/login',
          builder: (_, state) => LoginScreen(
            returnTo: state.uri.queryParameters['returnTo'] ?? '/admin',
          ),
        ),
        GoRoute(
          path: '/admin',
          builder: (_, __) => const AdminDashboardScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      title: '${AppBrand.name} Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}

class _AdminAuthRefresh extends ChangeNotifier {
  _AdminAuthRefresh(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
