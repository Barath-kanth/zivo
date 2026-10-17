import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/mode/mode_cubit.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/utils/auth_gate.dart';

/// Dual Client / Helper marks — short labels so nothing truncates.
class ModeSwitchCard extends StatelessWidget {
  const ModeSwitchCard({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ModeCubit, ModeState>(
      builder: (context, state) {
        final isHelper = state is HelperMode;
        final toggling = state is ModeToggling;
        final l = context.watch<LocaleCubit>();
        final palette = ZivoPalette.of(context);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Material(
          color: palette.card,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: EdgeInsets.all(compact ? 12 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Workspace',
                      style: AppTextStyles.capsLabel.copyWith(
                        fontSize: 10,
                        letterSpacing: 0.9,
                        color: palette.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    if (toggling)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.accent,
                        ),
                      )
                    else
                      Text(
                        isHelper ? 'Helper' : 'Client',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isHelper
                              ? palette.accent
                              : palette.textPrimary,
                        ),
                      ),
                  ],
                ),
                Gap(compact ? 10 : 12),
                Row(
                  children: [
                    Expanded(
                      child: _ModeLogo(
                        selected: !isHelper && !toggling,
                        label: l.t('home.client'),
                        status: !isHelper ? 'Active' : 'Switch',
                        icon: Icons.person_rounded,
                        // Selected Client = black tile; unselected uses palette.
                        accent: isDark ? Colors.white : const Color(0xFF1A1A1A),
                        onTap: toggling || !isHelper
                            ? null
                            : () => _switchTo(context, helper: false),
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: _ModeLogo(
                        selected: isHelper && !toggling,
                        label: l.t('home.helper'),
                        status: isHelper ? 'Active' : 'Switch',
                        icon: Icons.handshake_rounded,
                        accent: palette.accent,
                        onTap: toggling || isHelper
                            ? null
                            : () => _switchTo(context, helper: true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _switchTo(BuildContext context, {required bool helper}) async {
    final mode = context.read<ModeCubit>();
    final currentlyHelper = mode.state is HelperMode;
    if (helper == currentlyHelper) return;

    if (mode.state is GuestClientMode ||
        context.read<AuthBloc>().state is! AuthAuthenticated) {
      final ok = await requireAuth(context, returnTo: AppRoutes.shell);
      if (!ok || !context.mounted) return;
    }

    try {
      await mode.toggleMode();
      if (!context.mounted) return;
      context.go(AppRoutes.shell);
    } catch (_) {
      /* ModeCubit surfaces snackbars */
    }
  }
}

class _ModeLogo extends StatelessWidget {
  const _ModeLogo({
    required this.selected,
    required this.label,
    required this.status,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final String status;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(14);

    // Always-readable: selected solid accent; idle = bordered surface + primary ink.
    final Color bg;
    final Color fg;
    final Color border;
    if (selected) {
      bg = accent;
      fg = accent.computeLuminance() > 0.55 ? Colors.black : Colors.white;
      border = accent;
    } else {
      bg = isDark ? const Color(0xFF1A1A1A) : palette.surface;
      fg = palette.textPrimary;
      border = palette.border;
    }

    return Semantics(
      button: true,
      selected: selected,
      label: selected ? '$label, active' : 'Switch to $label',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
              border: Border.all(color: border, width: selected ? 0 : 1.5),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: fg),
                const Gap(6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                ),
                const Gap(3),
                Text(
                  status,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                    color: fg.withValues(alpha: selected ? 0.9 : 0.75),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
