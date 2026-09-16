import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/mode/mode_cubit.dart';
import 'package:hyperlocal/blocs/task/task_bloc.dart';
import 'package:hyperlocal/blocs/wallet/wallet_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/utils/auth_gate.dart';
import 'package:hyperlocal/ui/client/client_home_screen.dart';
import 'package:hyperlocal/ui/helper/helper_home_screen.dart';
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
      if (path == AppRoutes.createTask) return 1;
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
            context.read<TaskBloc>().add(TaskSubscribeToFeed());
            context.go(AppRoutes.shell);
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

          return Scaffold(
            extendBody: true,
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _buildBodyContent(isHelper, widget.child),
            ),
            bottomNavigationBar:
                _buildBottomNav(isHelper, modeState, selectedIndex),
          );
        },
      ),
    );
  }

  Widget _buildBodyContent(bool isHelper, Widget child) {
    // Determine if we are on the root route using GoRouterState
    final path = GoRouterState.of(context).uri.path;
    if (path == '/') {
      return isHelper
          ? const HelperHomeScreen(key: ValueKey('helper'))
          : const ClientHomeScreen(key: ValueKey('client'));
    }
    // Otherwise, render the pushed child (e.g. WalletScreen, ActiveJob)
    return child;
  }

  Widget _buildBottomNav(bool isHelper, ModeState modeState, int selectedIndex) {
    final items = isHelper
        ? [
            const _NavItem(icon: Icons.map_outlined, activeIcon: Icons.map, label: 'Jobs'),
            const _NavItem(icon: Icons.work_outline, activeIcon: Icons.work, label: 'Active'),
            const _NavItem(icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet, label: 'Earnings'),
            const _NavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Account'),
          ]
        : [
            const _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
            const _NavItem(icon: Icons.add_circle_outline, activeIcon: Icons.add_circle, label: 'Post'),
            const _NavItem(icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet, label: 'Wallet'),
            const _NavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Account'),
          ];

    final accentColor = isHelper ? AppColors.helperAccent : AppColors.accent;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        border: const Border(top: BorderSide(color: AppColors.borderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              // Navigation items
              ...List.generate(items.length, (i) {
                final item = items[i];
                final isSelected = selectedIndex == i;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _onNavTap(i, isHelper),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: isSelected ? BoxDecoration(
                        color: accentColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ) : null,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSelected ? item.activeIcon : item.icon,
                            color: isSelected ? accentColor : AppColors.textMuted,
                            size: 22,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.label,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: isSelected ? accentColor : AppColors.textMuted,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              // Mode Toggle
              const SizedBox(width: 8),
              ModeToggleWidget(isHelper: isHelper),
            ],
          ),
        ),
      ),
    );
  }

  void _onNavTap(int index, bool isHelper) async {
    if (index == 3) {
      if (!await requireAuth(context, returnTo: AppRoutes.account)) return;
      if (!mounted) return;
      context.go(AppRoutes.account);
      return;
    }
    if (isHelper) {
      if (index == 0) {
        context.go(AppRoutes.shell);
      } else if (index == 1) {
        final auth = context.read<AuthBloc>().state;
        final helperId =
            auth is AuthAuthenticated ? auth.profile.id : null;
        final activeTask = context
            .read<TaskBloc>()
            .getActiveTaskForHelper(helperId: helperId);
        if (activeTask == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No active job yet — accept one from Jobs.'),
            ),
          );
          return;
        }
        context.go('/job/${activeTask.id}/active');
      } else if (index == 2) {
        if (!await requireAuth(context, returnTo: AppRoutes.wallet)) return;
        if (!mounted) return;
        context.go(AppRoutes.wallet);
      }
    } else {
      if (index == 0) {
        context.go(AppRoutes.shell);
      } else if (index == 1) {
        if (!await requireAuth(context, returnTo: AppRoutes.createTask)) {
          return;
        }
        if (!mounted) return;
        if (!await requireVerified(context, returnTo: AppRoutes.createTask)) {
          return;
        }
        if (!mounted) return;
        context.push(AppRoutes.createTask);
      } else if (index == 2) {
        if (!await requireAuth(context, returnTo: AppRoutes.wallet)) return;
        if (!mounted) return;
        context.go(AppRoutes.wallet);
      }
    }
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
}
