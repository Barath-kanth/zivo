import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/ui/auth/login_screen.dart';
import 'package:hyperlocal/ui/auth/welcome_screen.dart';
import 'package:hyperlocal/ui/auth/otp_verify_screen.dart';
import 'package:hyperlocal/ui/auth/onboarding_screen.dart';
import 'package:hyperlocal/ui/shell/shell_screen.dart';
import 'package:hyperlocal/ui/client/task_creation/task_creation_screen.dart';
import 'package:hyperlocal/ui/client/task_tracking/task_tracking_screen.dart';
import 'package:hyperlocal/ui/client/wallet/wallet_screen.dart';
import 'package:hyperlocal/ui/client/shared_live_screen.dart';
import 'package:hyperlocal/ui/helper/job_feed/job_feed_screen.dart';
import 'package:hyperlocal/ui/helper/active_job/active_job_screen.dart';
import 'package:hyperlocal/ui/_shared/task_chat_screen.dart';
import 'package:hyperlocal/ui/account/account_screen.dart';
import 'package:hyperlocal/ui/account/settings_screen.dart';
import 'package:hyperlocal/ui/account/qualifications_screen.dart';
import 'package:hyperlocal/ui/account/reviews_screen.dart';
import 'package:hyperlocal/ui/account/quotes_screen.dart';
import 'package:hyperlocal/ui/account/guidelines_screen.dart';
import 'package:hyperlocal/ui/admin/admin_dashboard_screen.dart';

/// Named route paths — use these constants everywhere.
abstract class AppRoutes {
  /// Welcome gate (Zevoa-style). Phone/email form is [loginForm].
  static const String login = '/login';
  static const String loginForm = '/login/form';
  static const String otpVerify = '/otp';
  static const String onboarding = '/onboarding';
  static const String shell = '/';
  static const String createTask = '/task/create';
  static const String trackTask = '/task/:taskId/track';
  static const String taskChat = '/task/:taskId/chat';
  static const String activeJob = '/job/:taskId/active';
  static const String wallet = '/wallet';

  static String chatFor(String taskId, {String? title}) {
    final base = '/task/$taskId/chat';
    if (title == null || title.isEmpty) return base;
    return '$base?title=${Uri.encodeComponent(title)}';
  }
  static const String jobFeed = '/jobs';
  static const String account = '/account';
  static const String settings = '/settings';
  static const String qualifications = '/qualifications';
  static const String reviews = '/reviews';
  static const String quotes = '/quotes';
  static const String guidelines = '/guidelines';
  static const String opsKyc = '/ops/kyc';
  /// Separate admin console for per-user KYC review.
  static const String admin = '/admin';
  /// Family Assist shared live board (public token).
  static const String sharedLive = '/shared/:token';

  static String sharedLiveFor(String token) => '/shared/$token';
}

class AppRouter {
  AppRouter({required this.authBloc});

  final AuthBloc authBloc;
  bool _hasLanded = false;

  /// Root navigator — full-screen routes (login, OTP, KYC) must use this
  /// so pushes from inside [ShellRoute] are not swallowed.
  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();

  late final GoRouter config = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.shell,
    debugLogDiagnostics: false,
    redirect: _authGuard,
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
    routes: [
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (ctx, state) {
          final returnTo = state.uri.queryParameters['returnTo'];
          return _fadeTransition(
            state,
            WelcomeScreen(returnTo: returnTo),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.loginForm,
        name: 'loginForm',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (ctx, state) {
          final returnTo = state.uri.queryParameters['returnTo'];
          final signUp = state.uri.queryParameters['mode'] == 'signup';
          return _fadeTransition(
            state,
            LoginScreen(returnTo: returnTo, initialSignUp: signUp),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.otpVerify,
        name: 'otpVerify',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (ctx, state) {
          final extra = state.extra;
          String phone = '';
          String? freeCode;
          String? returnTo;
          String? deliveryWarning;
          var viaTextBee = false;
          if (extra is Map) {
            phone = extra['phone'] as String? ?? '';
            freeCode = extra['freeCode'] as String?;
            returnTo = extra['returnTo'] as String?;
            deliveryWarning = extra['deliveryWarning'] as String?;
            viaTextBee = extra['viaTextBee'] as bool? ?? false;
          } else if (extra is String) {
            phone = extra;
          }
          returnTo ??= state.uri.queryParameters['returnTo'];
          return _fadeTransition(
            state,
            OtpVerifyScreen(
              phone: phone,
              freeDevOtpCode: freeCode,
              returnTo: returnTo,
              deliveryWarning: deliveryWarning,
              viaTextBee: viaTextBee,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (ctx, state) => _fadeTransition(
          state,
          const OnboardingScreen(),
        ),
      ),
      ShellRoute(
        builder: (ctx, state, child) => ShellScreen(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.shell,
            name: 'home',
            pageBuilder: (ctx, state) => _noTransition(
              state,
              const SizedBox.shrink(),
            ),
          ),
          GoRoute(
            path: AppRoutes.wallet,
            name: 'wallet',
            pageBuilder: (ctx, state) => _slideTransition(
              state,
              const WalletScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.jobFeed,
            name: 'jobFeed',
            pageBuilder: (ctx, state) => _noTransition(
              state,
              const JobFeedScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.account,
            name: 'account',
            pageBuilder: (ctx, state) => _noTransition(
              state,
              const AccountScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.settings,
            name: 'settings',
            pageBuilder: (ctx, state) => _slideTransition(
              state,
              const SettingsScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.qualifications,
            name: 'qualifications',
            pageBuilder: (ctx, state) => _slideTransition(
              state,
              const QualificationsScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.reviews,
            name: 'reviews',
            pageBuilder: (ctx, state) => _slideTransition(
              state,
              const ReviewsScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.quotes,
            name: 'quotes',
            pageBuilder: (ctx, state) => _slideTransition(
              state,
              const QuotesScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.guidelines,
            name: 'guidelines',
            pageBuilder: (ctx, state) => _slideTransition(
              state,
              const GuidelinesScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.createTask,
            name: 'createTask',
            pageBuilder: (ctx, state) {
              TaskCategory? initial;
              final extra = state.extra;
              if (extra is TaskCategory) {
                initial = extra;
              } else if (extra is String) {
                initial = TaskCategory.fromString(extra);
              } else {
                final q = state.uri.queryParameters['category'];
                if (q != null) initial = TaskCategory.fromString(q);
              }
              return _noTransition(
                state,
                TaskCreationScreen(initialCategory: initial),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.admin,
        name: 'admin',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (ctx, state) => _slideTransition(
          state,
          const AdminDashboardScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.opsKyc,
        name: 'opsKyc',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (ctx, state) => _slideTransition(
          state,
          const AdminDashboardScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.trackTask,
        name: 'trackTask',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (ctx, state) => _slideTransition(
          state,
          TaskTrackingScreen(taskId: state.pathParameters['taskId']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.taskChat,
        name: 'taskChat',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (ctx, state) => _slideTransition(
          state,
          TaskChatScreen(
            taskId: state.pathParameters['taskId']!,
            taskTitle: state.uri.queryParameters['title'],
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.activeJob,
        name: 'activeJob',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (ctx, state) => _slideTransition(
          state,
          ActiveJobScreen(taskId: state.pathParameters['taskId']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.sharedLive,
        name: 'sharedLive',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (ctx, state) => _fadeTransition(
          state,
          SharedLiveScreen(token: state.pathParameters['token'] ?? ''),
        ),
      ),
    ],
    errorBuilder: (ctx, state) => Scaffold(
      body: Center(
        child: Text('Route not found: ${state.error}'),
      ),
    ),
  );

  static bool _isPublicBrowse(String loc) {
    return loc == AppRoutes.shell ||
        loc == AppRoutes.jobFeed ||
        loc == AppRoutes.guidelines ||
        loc == AppRoutes.login ||
        loc == AppRoutes.loginForm ||
        loc == AppRoutes.otpVerify ||
        loc.startsWith('/shared/');
  }

  static bool _requiresAuth(String loc) {
    if (loc == AppRoutes.createTask) return true;
    if (loc == AppRoutes.wallet) return true;
    if (loc == AppRoutes.account) return true;
    if (loc == AppRoutes.settings) return true;
    if (loc == AppRoutes.qualifications) return true;
    if (loc == AppRoutes.reviews) return true;
    if (loc == AppRoutes.quotes) return true;
    if (loc == AppRoutes.opsKyc) return true;
    if (loc == AppRoutes.admin) return true;
    if (loc == AppRoutes.onboarding) return true;
    if (loc.startsWith('/task/') && loc.endsWith('/track')) return true;
    if (loc.startsWith('/task/') && loc.endsWith('/chat')) return true;
    if (loc.startsWith('/job/') && loc.endsWith('/active')) return true;
    return false;
  }

  String _loginWithReturn(GoRouterState state) {
    final returnTo = Uri.encodeComponent(state.uri.toString());
    return '${AppRoutes.login}?returnTo=$returnTo';
  }

  String? _authGuard(BuildContext context, GoRouterState state) {
    final uri = state.uri;
    // OAuth / Supabase may bounce back with ?error=... — land on login, no crash.
    final oauthError = uri.queryParameters['error'] ??
        uri.queryParameters['error_code'];
    if (oauthError != null && oauthError.isNotEmpty) {
      final msg = uri.queryParameters['error_description'] ??
          uri.queryParameters['error'] ??
          'Google sign-in failed';
      Future.microtask(() {
        authBloc.add(AuthOAuthCallbackFailed(
          Uri.decodeComponent(msg.replaceAll('+', ' ')),
        ));
      });
      if (state.matchedLocation != AppRoutes.login) {
        return AppRoutes.login;
      }
      return null;
    }

    if (uri.queryParameters.containsKey('code')) {
      Future.microtask(() => authBloc.add(AuthCheckRequested()));
    }

    final authState = authBloc.state;
    final isAuthenticated = authState is AuthAuthenticated;
    final isSignedIn = isAuthenticated || authState is AuthNeedsOnboarding;
    final loc = state.matchedLocation;
    final isLoggingIn =
        loc == AppRoutes.login || loc == AppRoutes.loginForm;
    final isOtp = loc == AppRoutes.otpVerify;
    final isOnboarding = loc == AppRoutes.onboarding;
    // Keep AuthFailure / loading on OTP screen so Verify errors stay visible.
    final isOtpFlow = authState is AuthOtpSent ||
        authState is AuthFailure ||
        (authState is AuthLoading && isOtp);

    if (authState is AuthUnauthenticated) {
      _hasLanded = false;
    }

    // Guests: never stay on KYC after a stale browser URL.
    if (isOnboarding && !isSignedIn && authState is! AuthLoading) {
      return AppRoutes.shell;
    }

    if (authState is AuthLoading) return null;

    if (isOtpFlow && (isLoggingIn || isOtp)) return null;

    // Guest browse: allow public routes without forcing login.
    if (!isSignedIn) {
      if (_requiresAuth(loc)) {
        return _loginWithReturn(state);
      }
      if (_isPublicBrowse(loc) || loc == AppRoutes.shell) {
        return null;
      }
      return AppRoutes.shell;
    }

    // Signed in: leave login/OTP for intended destination.
    if (isAuthenticated || authState is AuthNeedsOnboarding) {
      if (isLoggingIn || isOtp) {
        final returnTo = uri.queryParameters['returnTo'];
        if (returnTo != null && returnTo.isNotEmpty) {
          try {
            return Uri.decodeComponent(returnTo);
          } catch (_) {
            return AppRoutes.shell;
          }
        }
        return AppRoutes.shell;
      }
      if (!_hasLanded && loc == AppRoutes.shell) {
        _hasLanded = true;
      }
    }
    return null;
  }

  CustomTransitionPage _fadeTransition(GoRouterState state, Widget child) {
    return CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (ctx, animation, _, c) =>
          FadeTransition(opacity: animation, child: c),
    );
  }

  CustomTransitionPage _slideTransition(GoRouterState state, Widget child) {
    return CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (ctx, animation, _, c) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: animation, child: c),
      ),
    );
  }

  CustomTransitionPage _noTransition(GoRouterState state, Widget child) {
    return CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: Duration.zero,
      transitionsBuilder: (_, __, ___, c) => c,
    );
  }
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final dynamic _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
