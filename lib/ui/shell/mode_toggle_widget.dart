import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/mode/mode_cubit.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/utils/auth_gate.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';

/// A compact animated toggle button placed in the navigation bar that switches
/// between Client Mode and Helper Mode.
class ModeToggleWidget extends StatelessWidget {
  const ModeToggleWidget({super.key, required this.isHelper});
  final bool isHelper;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ModeCubit, ModeState>(
      builder: (context, state) {
        final isToggling = state is ModeToggling;

        final l = context.watch<LocaleCubit>();
        final palette = ZivoPalette.of(context);
        final switchLabel = isHelper
            ? l.t('nav.switchClient')
            : l.t('nav.switchHelper');
        return Semantics(
          button: true,
          enabled: !isToggling,
          label: switchLabel,
          child: Tooltip(
            message: switchLabel,
            child: Material(
              color: palette.accent,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: isToggling ? null : () => _onToggle(context),
                child: SizedBox(
                  width: 56,
                  height: 56,
            child: isToggling
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isHelper
                            ? Icons.person_search_rounded
                            : Icons.handshake_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            isHelper ? l.t('home.client') : l.t('home.helper'),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 9,
                              height: 1.0,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _onToggle(BuildContext context) async {
    final modeState = context.read<ModeCubit>().state;
    if (modeState is GuestClientMode ||
        context.read<AuthBloc>().state is! AuthAuthenticated) {
      await requireAuth(context, returnTo: AppRoutes.shell);
      return;
    }

    final targetLabel = modeState is ClientMode ? 'Helper' : 'Client';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Switch to $targetLabel Mode',
              style: AppTextStyles.headingMedium,
            ),
            const SizedBox(height: 8),
            Text(
              modeState is ClientMode
                  ? 'Find nearby tasks, manage your availability and track your earnings.'
                  : 'In Client Mode, you can post tasks, fund your wallet, and track helpers in real time.',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.borderColor),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: AppTextStyles.bodyLarge
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final goingHelper = modeState is ClientMode;
                      if (goingHelper) {
                        if (!await requireVerified(
                          context,
                          returnTo: AppRoutes.shell,
                          message:
                              'Verify your identity before Helper mode. Zivo Admin must approve your documents.',
                        )) {
                          return;
                        }
                        if (!context.mounted) return;
                      }
                      try {
                        await context.read<ModeCubit>().toggleMode();
                      } catch (e) {
                        if (!context.mounted) return;
                        final msg = e
                            .toString()
                            .replaceFirst('AuthException: ', '');
                        final auth = context.read<AuthBloc>().state;
                        final needsOnboarding = auth is AuthAuthenticated &&
                            auth.profile.needsKycForHelper;
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: AppColors.cardDark,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                          ),
                          builder: (sheetCtx) => Padding(
                            padding:
                                const EdgeInsets.fromLTRB(24, 20, 24, 32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Verify identity',
                                  style: AppTextStyles.headingMedium,
                                ),
                                const SizedBox(height: 10),
                                Text(msg, style: AppTextStyles.bodyMedium),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(sheetCtx);
                                      if (needsOnboarding) {
                                        context.push(AppRoutes.onboarding);
                                      }
                                    },
                                    child: Text(
                                      needsOnboarding
                                          ? 'Start verification'
                                          : 'OK',
                                      style: AppTextStyles.buttonLabel
                                          .copyWith(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZivoPalette.of(context).accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Switch',
                      style: AppTextStyles.buttonLabel
                          .copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
