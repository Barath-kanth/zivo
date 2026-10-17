import 'package:hyperlocal/ui/_shared/shell_route_content.dart';
import 'package:hyperlocal/ui/_shared/desktop_sidebar.dart';
import 'package:hyperlocal/ui/_shared/glass_dock.dart';
import 'package:hyperlocal/ui/_shared/app_viewport.dart';
import 'package:hyperlocal/ui/_shared/a11y_landmarks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/mode/mode_cubit.dart';
import 'package:hyperlocal/blocs/task/task_bloc.dart';
import 'package:hyperlocal/blocs/wallet/wallet_bloc.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/utils/auth_gate.dart';
import 'package:hyperlocal/ui/client/client_home_screen.dart';
import 'package:hyperlocal/ui/helper/helper_home_screen.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'mode_toggle_widget.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.child});
  final Widget child;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  Type? _prevModeType;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final userId = authState.profile.id;
      // Prefer local workspace pref (refresh keeps helper/client; first open → client).
      context.read<ModeCubit>().initFromProfile(authState.profile);
      context.read<WalletBloc>()
        ..add(WalletFetchRequested(userId))
        ..add(WalletSubscribeRequested(userId));
    } else {
      context.read<ModeCubit>().initGuest();
    }
  }

  int _calculateSelectedIndex(bool isHelper, String path) {
    if (path == AppRoutes.account ||
        path == AppRoutes.settings ||
        path == AppRoutes.qualifications ||
        path == AppRoutes.reviews ||
        path == AppRoutes.quotes ||
        path == AppRoutes.guidelines) {
      return 3;
    }
    if (isHelper) {
      if (path == AppRoutes.wallet) return 2;
      if (path.startsWith('/job/') && path.endsWith('/active')) return 1;
      return 0;
    } else {
      if (path == AppRoutes.myTasks) return 1;
      if (path == AppRoutes.wallet) return 2;
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, authState) {
        if (authState is AuthAuthenticated) {
          final userId = authState.profile.id;
          context.read<ModeCubit>().initFromProfile(authState.profile);
          context.read<WalletBloc>()
            ..add(WalletFetchRequested(userId))
            ..add(WalletSubscribeRequested(userId));
        } else if (authState is AuthUnauthenticated) {
          context.read<ModeCubit>().initGuest();
        }
      },
      child: BlocConsumer<ModeCubit, ModeState>(
        listenWhen: (prev, next) => prev.runtimeType != next.runtimeType,
        listener: (context, state) {
          final prev = _prevModeType;
          _prevModeType = state.runtimeType;

          if (state is HelperMode) {
            context.read<TaskBloc>()
              ..add(TaskSubscribeToFeed())
              ..add(TaskFetchHelperActive())
              ..add(TaskFetchNearbyTasks());
            // Force home only on an intentional switch into helper (Client →
            // ModeToggling → Helper). Skip on remount/restore so refresh can
            // keep /wallet or Active Job under the same workspace.
            if (prev == ClientMode ||
                prev == ModeHelperBlocked ||
                prev == ModeToggling) {
              context.go(AppRoutes.shell);
            }
          } else if (state is ClientMode) {
            context.read<TaskBloc>().add(TaskUnsubscribeFromFeed());
            if (!state.profile.isGuest) {
              context
                  .read<TaskBloc>()
                  .add(TaskFetchClientTasks(state.profile.id));
            }
            // Only when switching Helper → Client (not after Add account).
            if (prev == HelperMode) {
              context.go(AppRoutes.shell);
            }
          } else if (state is GuestClientMode) {
            context.read<TaskBloc>().add(TaskUnsubscribeFromFeed());
          }
        },
        builder: (context, modeState) {
          final isHelper = modeState is HelperMode;
          final path = GoRouterState.of(context).uri.path;
          final selectedIndex = _calculateSelectedIndex(isHelper, path);

          final desktop = MediaQuery.sizeOf(context).width >= 1100;
          // Hide glass dock on create-task so Continue/Post is never buried under it.
          final hideDock = desktop ||
              MediaQuery.viewInsetsOf(context).bottom > 0 ||
              path == AppRoutes.createTask;
          final palette = ZivoPalette.of(context);
          return Scaffold(
            backgroundColor: palette.canvas,
            extendBody: !desktop && !hideDock,
            // No floating Access button on mobile — it covered Track / Accept / Top up.
            body: Row(
              children: [
                if (desktop)
                  A11yLandmark.navigation(
                    label: isHelper
                        ? 'Helper workspace navigation'
                        : 'Client workspace navigation',
                    child: DesktopSidebar(
                      isHelper: isHelper,
                      selectedIndex: selectedIndex,
                      destinations: _navigationItems(isHelper)
                          .where((d) =>
                              d.label !=
                              context.watch<LocaleCubit>().t('nav.account'))
                          .toList(),
                      onDestinationSelected: (index) =>
                          _onNavTap(index, isHelper),
                      screenHint:
                          'Zivo ${isHelper ? 'helper' : 'client'} screen at $path',
                    ),
                  ),
                Expanded(
                  child: A11yLandmark.main(
                    label: isHelper ? 'Helper main content' : 'Client main content',
                    child: AppViewport(
                      child: _buildBodyContent(isHelper, widget.child),
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: hideDock
                ? null
                : A11yLandmark.navigation(
                    label: 'Primary mobile navigation',
                    child: _buildBottomNav(isHelper, modeState, selectedIndex),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildBodyContent(bool isHelper, Widget child) {
    final path = GoRouterState.of(context).uri.path;
    final isHome = path == AppRoutes.shell;
    final desktop = MediaQuery.sizeOf(context).width >= 1100;

    // Desktop client: navigator stays in a fixed slot; activity rail is a sibling
    // so Wallet / Account / Post never tear down the right-hand panel.
    if (!isHelper && desktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ShellRouteContent(
              isHome: isHome,
              routedChild: child,
              home: const ClientHomeScreen(
                key: ValueKey('client-services'),
                pane: ClientHomePane.servicesOnly,
                forceDesktopChrome: true,
              ),
            ),
          ),
          if (isHome) const SizedBox(
            width: 320,
            child: ClientHomeScreen(
              key: ValueKey('client-rail'),
              pane: ClientHomePane.railOnly,
              forceDesktopChrome: true,
            ),
          ),
        ],
      );
    }

    if (desktop) {
      return Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: ShellRouteContent(isHome: isHome, routedChild: child,
          home: isHome ? (isHelper ? const HelperHomeScreen(key: ValueKey('helper'))
            : const ClientHomeScreen(key: ValueKey('client'))) : null),
      ));
    }
    return ShellRouteContent(
      isHome: isHome,
      routedChild: child,
      home: isHome
          ? (isHelper
              ? const HelperHomeScreen(key: ValueKey('helper'))
              : const ClientHomeScreen(key: ValueKey('client')))
          : null,
    );
  }

  List<AppNavDestination> _navigationItems(bool isHelper) {
    final l = context.watch<LocaleCubit>();
    return isHelper
        ? [
            AppNavDestination(
                icon: Icons.map_outlined,
                activeIcon: Icons.map,
                label: l.t('nav.jobs')),
            AppNavDestination(
                icon: Icons.work_outline,
                activeIcon: Icons.work,
                label: l.t('nav.active')),
            AppNavDestination(
                icon: Icons.account_balance_wallet_outlined,
                activeIcon: Icons.account_balance_wallet,
                label: l.t('wallet.earningsTitle')),
            AppNavDestination(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: l.t('nav.account')),
          ]
        : [
            AppNavDestination(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: l.t('nav.home')),
            AppNavDestination(
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long,
                label: l.t('nav.myTasks')),
            AppNavDestination(
                icon: Icons.account_balance_wallet_outlined,
                activeIcon: Icons.account_balance_wallet,
                label: l.t('nav.wallet')),
            AppNavDestination(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: l.t('nav.account')),
          ];
  }

  Widget _buildBottomNav(bool isHelper, ModeState modeState, int selectedIndex) {
    final items = _navigationItems(isHelper);
    final palette = ZivoPalette.of(context);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return GlassDock(
      child: Row(
        children: [
          ...List.generate(items.length, (i) {
            final item = items[i];
            final isSelected = selectedIndex == i;
            return Expanded(
              child: Semantics(
                selected: isSelected,
                button: true,
                label: item.label,
                child: Tooltip(
                  message: item.label,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => _onNavTap(i, isHelper),
                      child: AnimatedContainer(
                        duration: reducedMotion ? Duration.zero
                            : const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        constraints: const BoxConstraints(minHeight: 56),
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? palette.glassSelection
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: ExcludeSemantics(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected ? item.activeIcon : item.icon,
                                color: isSelected
                                    ? palette.accent
                                    : palette.textSecondary,
                                size: 22,
                              ),
                              const SizedBox(height: 3),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: isSelected
                                        ? palette.accent
                                        : palette.textSecondary,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    fontSize: 11,
                                    height: 1.1,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(width: 6),
          // Always-visible Client ↔ Helper switch on mobile dock.
          ModeToggleWidget(isHelper: isHelper),
        ],
      ),
    );
  }

  void _onNavTap(int index, bool isHelper) async {
    if (index == 3) {
      // After login, open client home — not Account. Signed-in users go Account.
      final wasGuest = context.read<AuthBloc>().state is! AuthAuthenticated;
      if (!await requireAuth(context, returnTo: AppRoutes.shell)) return;
      if (!mounted) return;
      if (wasGuest) {
        context.go(AppRoutes.shell);
      } else {
        context.go(AppRoutes.account);
      }
      return;
    }
    if (isHelper) {
      if (index == 0) {
        context.go(AppRoutes.shell);
      } else if (index == 1) {
        final auth = context.read<AuthBloc>().state;
        if (auth is! AuthAuthenticated) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sign in to view your active job.')),
          );
          return;
        }
        final activeTask = await context
            .read<TaskBloc>()
            .resolveHelperActiveTask(helperId: auth.profile.id);
        if (!mounted) return;
        if (activeTask == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No active job yet — accept one from Jobs.'),
            ),
          );
          return;
        }
        // Push so Shell stays under Active Job — back returns to helper home.
        context.push('/job/${activeTask.id}/active');
      } else if (index == 2) {
        if (!await requireAuth(context, returnTo: AppRoutes.wallet)) return;
        if (!mounted) return;
        context.go(AppRoutes.wallet);
      }
    } else {
      if (index == 0) {
        context.go(AppRoutes.shell);
      } else if (index == 1) {
        if (!await requireAuth(context, returnTo: AppRoutes.myTasks)) return;
        if (!mounted) return;
        context.go(AppRoutes.myTasks);
      } else if (index == 2) {
        if (!await requireAuth(context, returnTo: AppRoutes.wallet)) return;
        if (!mounted) return;
        context.go(AppRoutes.wallet);
      }
    }
  }
}
