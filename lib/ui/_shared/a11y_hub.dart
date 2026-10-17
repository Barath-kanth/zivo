import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/blocs/a11y/a11y_cubit.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/core/utils/speak_text.dart';
import 'package:hyperlocal/ui/_shared/a11y_voice_assist.dart';
import 'package:hyperlocal/ui/_shared/a11y_widgets.dart';
import 'package:hyperlocal/ui/accessibility/ability_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Soft invite once — never a permanent top banner.
Future<void> maybeShowA11yInvite(BuildContext context) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('zivo_a11y_invite_seen') == true) return;
    await prefs.setBool('zivo_a11y_invite_seen', true);
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  await Future<void>.delayed(const Duration(milliseconds: 900));
  if (!context.mounted) return;
  if (context.read<A11yCubit>().enabled) return;
  await showA11yHub(context, inviteMode: true);
}

/// Single Accessibility hub — same sheet on mobile FAB and desktop sidebar.
Future<void> showA11yHub(
  BuildContext context, {
  bool inviteMode = false,
  String screenHint = 'Zivo app screen',
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: ZivoPalette.of(context).card,
    isScrollControlled: true,
    // Don't clip Arabic/CJK language chips at the sheet edge.
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _A11yHubSheet(
      inviteMode: inviteMode,
      screenHint: screenHint,
    ),
  );
}

class _A11yHubSheet extends StatelessWidget {
  const _A11yHubSheet({
    required this.inviteMode,
    required this.screenHint,
  });

  final bool inviteMode;
  final String screenHint;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    final palette = ZivoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BlocBuilder<LocaleCubit, Locale>(
      builder: (context, locale) {
        final l = context.read<LocaleCubit>();
        return BlocBuilder<A11yCubit, bool>(
          builder: (context, on) {
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: SingleChildScrollView(
                // Arabic / CJK chips overflow their line box — never clip them.
                clipBehavior: Clip.none,
                padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const Gap(14),
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color:
                                AppColors.helperAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.accessibility_new_rounded,
                            color: AppColors.helperAccent,
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                inviteMode
                                    ? l.t('a11y.inviteTitle')
                                    : l.t('a11y.title'),
                                style: AppTextStyles.headingMedium.copyWith(
                                  color: palette.textPrimary,
                                ),
                              ),
                              Text(
                                inviteMode
                                    ? l.t('a11y.inviteBody')
                                    : l.t('a11y.body'),
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: palette.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Gap(16),
                    Text(
                      l.t('a11y.language'),
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    Text(
                      l.t('a11y.languageSub'),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                    const Gap(10),
                    // clipBehavior none — Arabic/Chinese descenders must not hide.
                    Wrap(
                      spacing: 8,
                      runSpacing: 12,
                      clipBehavior: Clip.none,
                      children: [
                        for (final code in const [
                          'en',
                          'si',
                          'ta',
                          'hi',
                          'es',
                          'fr',
                          'ar',
                          'zh',
                        ])
                          ChoiceChip(
                            label: Text(
                              l.t('lang.$code'),
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ),
                            visualDensity: VisualDensity.standard,
                            materialTapTargetSize:
                                MaterialTapTargetSize.padded,
                            selected: locale.languageCode == code,
                            onSelected: (_) async {
                              // Keep the hub open — MaterialApp must NOT remount
                              // on locale change (that caused a blank white screen).
                              await context
                                  .read<LocaleCubit>()
                                  .setLocale(code);
                            },
                          ),
                      ],
                    ),
                    const Gap(20),
                    AbilityPicker(closeSheet: () => Navigator.pop(context)),
                  const Gap(12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: on,
                    onChanged: (v) => context.read<A11yCubit>().setEnabled(v),
                    title: Text(
                      on ? l.t('a11y.modeOn') : l.t('a11y.modeOff'),
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      l.t('a11y.modeSubtitle'),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.helperAccent,
                  ),
                  if (on) ...[
                    const Gap(8),
                    _HubAction(
                      icon: Icons.mic_rounded,
                      color: AppColors.helperAccent,
                      title: l.t('a11y.speak'),
                      subtitle: l.t('a11y.speakSub'),
                      onTap: () {
                        Navigator.pop(context);
                        showA11yVoiceAssist(context);
                      },
                    ),
                    _HubAction(
                      icon: Icons.visibility_outlined,
                      color: isDark ? palette.accent : Colors.black,
                      title: speakingListenable.value
                          ? 'Stop'
                          : l.t('a11y.describe'),
                      subtitle: l.t('a11y.describeSub'),
                      onTap: () {
                        Navigator.pop(context);
                        showA11yDescribeSheet(context, hint: screenHint);
                      },
                    ),
                    _HubAction(
                      icon: Icons.volume_up_rounded,
                      color: AppColors.helperAccent,
                      title: speakingListenable.value
                          ? 'Stop'
                          : l.t('a11y.readTips'),
                      subtitle: l.t('a11y.readTipsSub'),
                      onTap: () {
                        if (speakingListenable.value) {
                          stopSpeaking();
                        } else {
                          speakText(
                            l.t('a11y.modeSubtitle'),
                            lang: l.code,
                          );
                        }
                      },
                    ),
                  ] else ...[
                    const Gap(8),
                    FilledButton(
                      onPressed: () async {
                        await context.read<A11yCubit>().setEnabled(true);
                        if (!context.mounted) return;
                        speakText(
                          l.t('a11y.enable'),
                          lang: l.code,
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            isDark ? palette.accent : Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(l.t('a11y.enable')),
                    ),
                  ],
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        inviteMode ? l.t('a11y.notNow') : l.t('a11y.close'),
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _HubAction extends StatelessWidget {
  const _HubAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark ? const Color(0xFF242424) : AppColors.backgroundDark,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  child: Icon(icon, size: 20),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: palette.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One FAB — opens the hub (no permanent top bar).
class A11yHubFab extends StatelessWidget {
  const A11yHubFab({super.key, this.screenHint = 'Zivo app screen'});

  final String screenHint;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LocaleCubit, Locale>(
      builder: (context, _) {
        final l = context.read<LocaleCubit>();
        return BlocBuilder<A11yCubit, bool>(
          builder: (context, on) {
            return FloatingActionButton.extended(
              heroTag: 'a11y-hub',
              onPressed: () => showA11yHub(context, screenHint: screenHint),
              backgroundColor: on ? AppColors.helperAccent : Colors.black,
              foregroundColor: Colors.white,
              elevation: 3,
              extendedPadding: const EdgeInsets.symmetric(horizontal: 14),
              extendedIconLabelSpacing: 6,
              icon: Icon(
                on
                    ? Icons.accessibility_new_rounded
                    : Icons.accessibility_new_outlined,
                size: 20,
              ),
              label: Text(
                on ? l.t('fab.a11y') : l.t('fab.access'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
