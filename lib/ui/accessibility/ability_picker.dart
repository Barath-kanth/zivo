import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/blocs/a11y/a11y_cubit.dart';
import 'package:hyperlocal/blocs/ability/ability_cubit.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/ui/accessibility/access_audit_sheet.dart';
import 'package:hyperlocal/ui/accessibility/doorstep_talk_sheet.dart';
import 'package:hyperlocal/ui/accessibility/say_it_sheet.dart';
import 'package:hyperlocal/ui/accessibility/zivo_eyes_sheet.dart';

const _icons = <String, IconData>{
  'visual': Icons.visibility_off_rounded,
  'hearing': Icons.hearing_disabled_rounded,
  'speech': Icons.record_voice_over_rounded,
  'mobility': Icons.accessible_rounded,
  'cognitive': Icons.menu_book_rounded,
};

/// "How should Zivo adapt to you?" — pick abilities, get the matching AI tools.
/// Optional and private; nothing is sent to clients unless the helper turns disclosure on.
class AbilityPicker extends StatefulWidget {
  const AbilityPicker({super.key, required this.closeSheet});

  /// Pops the host sheet before opening a tool.
  final VoidCallback closeSheet;

  @override
  State<AbilityPicker> createState() => _AbilityPickerState();
}

class _AbilityPickerState extends State<AbilityPicker> {
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: context.read<AbilityCubit>().state.note);
    // Signed-in users: make sure the server has the profile this device holds.
    context.read<AbilityCubit>().resync();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final palette = ZivoPalette.of(context);
    return BlocBuilder<AbilityCubit, AbilityProfile>(
      builder: (context, p) {
        final cubit = context.read<AbilityCubit>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.t('ab.title'),
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w800,
                color: palette.textPrimary,
              ),
            ),
            const Gap(2),
            Text(
              l.t('ab.sub'),
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textMuted,
                height: 1.35,
              ),
            ),
            const Gap(10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in kAbilityKeys)
                  FilterChip(
                    avatar: Icon(_icons[k], size: 18),
                    label: Text(l.t('ab.$k')),
                    selected: p.has(k),
                    showCheckmark: false,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onSelected: (_) async {
                      await cubit.toggle(k);
                      // Low-vision / hearing users get the big-text, read-aloud mode automatically.
                      if ((k == 'visual' || k == 'cognitive') &&
                          cubit.state.has(k) &&
                          context.mounted) {
                        context.read<A11yCubit>().setEnabled(true);
                      }
                    },
                  ),
              ],
            ),
            const Gap(12),
            _ToolTile(
              icon: Icons.accessible_forward_rounded,
              color: AppColors.brandPurple,
              title: l.t('tool.audit'),
              subtitle: l.t('tool.auditSub'),
              onTap: () {
                widget.closeSheet();
                showAccessAudit(context);
              },
            ),
            if (!p.isEmpty) ...[
              if (p.has('visual'))
                _ToolTile(
                  icon: Icons.photo_camera_rounded,
                  color: const Color(0xFF0F766E),
                  title: l.t('tool.eyes'),
                  subtitle: l.t('tool.eyesSub'),
                  onTap: () {
                    widget.closeSheet();
                    showZivoEyes(context);
                  },
                ),
              if (p.has('hearing'))
                _ToolTile(
                  icon: Icons.hearing_rounded,
                  color: const Color(0xFF1D4ED8),
                  title: l.t('tool.doorstep'),
                  subtitle: l.t('tool.doorstepSub'),
                  onTap: () {
                    widget.closeSheet();
                    showDoorstepTalk(context);
                  },
                ),
              if (p.has('speech') || p.has('hearing'))
                _ToolTile(
                  icon: Icons.chat_bubble_rounded,
                  color: const Color(0xFFBE185D),
                  title: l.t('tool.say'),
                  subtitle: l.t('tool.saySub'),
                  onTap: () {
                    widget.closeSheet();
                    showSayIt(context);
                  },
                ),
              if (p.has('cognitive'))
                _ToolTile(
                  icon: Icons.short_text_rounded,
                  color: AppColors.brandPurple,
                  title: l.t('tool.easy'),
                  subtitle: l.t('tool.easySub'),
                  onTap: () {
                    widget.closeSheet();
                    showEasyRead(context);
                  },
                ),
              const Gap(4),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: p.disclose,
                onChanged: cubit.setDisclose,
                title: Text(
                  l.t('ab.disclose'),
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                subtitle: Text(
                  l.t('ab.discloseSub'),
                  style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
                ),
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.helperAccent,
              ),
              if (p.disclose)
                TextField(
                  controller: _note,
                  maxLength: 240,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: l.t('ab.noteHint'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: cubit.setNote,
                  onTapOutside: (_) => cubit.setNote(_note.text),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
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
      child: Semantics(
        button: true,
        label: '$title. $subtitle',
        child: Material(
          color: color.withValues(alpha: isDark ? 0.18 : 0.08),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                            fontWeight: FontWeight.w800,
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
      ),
    );
  }
}
