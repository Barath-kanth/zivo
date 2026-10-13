import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/blocs/a11y/a11y_cubit.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/utils/speak_text.dart';
import 'package:hyperlocal/ui/_shared/a11y_voice_assist.dart';
import 'package:hyperlocal/ui/_shared/a11y_widgets.dart';
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
  // Delay so home paints first — invitation is optional, not blocking.
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
    backgroundColor: Colors.white,
    isScrollControlled: true,
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
    return BlocBuilder<A11yCubit, bool>(
      builder: (context, on) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderColor,
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
                      color: AppColors.helperAccent.withValues(alpha: 0.12),
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
                              ? 'Need Speak or larger text?'
                              : 'Accessibility',
                          style: AppTextStyles.headingMedium,
                        ),
                        Text(
                          inviteMode
                              ? 'Optional — turn on only if you want voice help, read aloud, or Describe.'
                              : 'Speak, Describe, and Read aloud stay in this hub — not a bar on every screen.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textMuted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Gap(16),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: on,
                onChanged: (v) => context.read<A11yCubit>().setEnabled(v),
                title: Text(
                  on ? 'Accessibility Mode on' : 'Turn on Accessibility Mode',
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  'Larger text, Speak your need, Describe this screen, Read aloud, chat captions.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textMuted,
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
                  title: 'Speak',
                  subtitle: 'Say what you need — we post and announce updates',
                  onTap: () {
                    Navigator.pop(context);
                    showA11yVoiceAssist(context);
                  },
                ),
                _HubAction(
                  icon: Icons.visibility_outlined,
                  color: Colors.black,
                  title: speakingListenable.value ? 'Stop reading' : 'Describe',
                  subtitle: 'Hear what’s on this screen',
                  onTap: () {
                    Navigator.pop(context);
                    showA11yDescribeSheet(context, hint: screenHint);
                  },
                ),
                _HubAction(
                  icon: Icons.volume_up_rounded,
                  color: AppColors.helperAccent,
                  title: speakingListenable.value ? 'Stop reading' : 'Read tips',
                  subtitle: 'Quick reminder of Speak and Describe',
                  onTap: () {
                    if (speakingListenable.value) {
                      stopSpeaking();
                    } else {
                      speakText(
                        'Accessibility is on. Use Speak to post help by voice. '
                        'Use Describe to hear this screen. Use Stop when you want silence.',
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
                      'Accessibility on. Open this Accessibility button anytime for Speak and Describe.',
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Enable Accessibility'),
                ),
              ],
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(inviteMode ? 'Not now' : 'Close'),
              ),
            ],
          ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFF6F6F6),
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
                        ),
                      ),
                      Text(
                        subtitle,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
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
    return BlocBuilder<A11yCubit, bool>(
      builder: (context, on) {
        return FloatingActionButton.extended(
          heroTag: 'a11y-hub',
          onPressed: () => showA11yHub(context, screenHint: screenHint),
          backgroundColor: on ? AppColors.helperAccent : Colors.black,
          foregroundColor: Colors.white,
          icon: Icon(
            on
                ? Icons.accessibility_new_rounded
                : Icons.accessibility_new_outlined,
          ),
          label: Text(on ? 'A11y' : 'Access'),
        );
      },
    );
  }
}
