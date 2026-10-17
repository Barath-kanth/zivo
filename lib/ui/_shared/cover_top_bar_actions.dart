import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/utils/auth_gate.dart';

/// Desktop top bar: wallet + account, right-aligned.
/// Mobile: wallet only (Account stays in the bottom dock).
class CoverTopBarActions extends StatelessWidget {
  const CoverTopBarActions({super.key, this.showAccount = false});

  /// True on desktop chrome (≥1100 or forceDesktopChrome).
  final bool showAccount;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1100;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _CoverWalletPill(),
        if (showAccount) ...[
          const SizedBox(width: 8),
          const _CoverAccountPill(),
        ],
      ],
    );
  }
}

class _CoverWalletPill extends StatelessWidget {
  const _CoverWalletPill();

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final wallet =
            state is AuthAuthenticated ? state.profile.walletBalance : 0.0;
        return Material(
          color: palette.card,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => context.go(AppRoutes.wallet),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 16,
                    color: palette.textPrimary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppConfig.money(wallet),
                    style: AppTextStyles.moneyMeta.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CoverAccountPill extends StatelessWidget {
  const _CoverAccountPill();

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    final label = context.watch<LocaleCubit>().t('nav.account');
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () async {
          // Login lands on home; open Account only when already signed in.
          if (!await requireAuth(context, returnTo: AppRoutes.shell)) return;
          if (!context.mounted) return;
          context.go(AppRoutes.account);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 16,
                color: palette.textPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
