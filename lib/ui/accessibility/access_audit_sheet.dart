import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
import 'package:hyperlocal/core/utils/speak_text.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/ui/accessibility/zivo_eyes_sheet.dart';
import 'package:image_picker/image_picker.dart';

/// Client photographs the entrance; Gemini returns stairs/ramp/door notes for mobility helpers.
Future<Map<String, dynamic>?> showAccessAudit(
  BuildContext context, {
  String? taskId,
}) {
  final palette = ZivoPalette.of(context);
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: palette.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _AccessAuditSheet(taskId: taskId),
  );
}

class _AccessAuditSheet extends StatefulWidget {
  const _AccessAuditSheet({this.taskId});
  final String? taskId;

  @override
  State<_AccessAuditSheet> createState() => _AccessAuditSheetState();
}

class _AccessAuditSheetState extends State<_AccessAuditSheet> {
  bool _busy = false;
  Map<String, dynamic>? _result;

  Future<void> _shoot(ImageSource source) async {
    final l = context.read<LocaleCubit>();
    final lang = aiLang(context);
    final repo = context.read<TaskRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 72,
        maxWidth: 1400,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _busy = true;
        _result = null;
      });
      speakText(l.t('audit.working'), lang: l.code);
      final Map<String, dynamic> res;
      if (widget.taskId != null && widget.taskId!.isNotEmpty) {
        final out = await repo.attachAccessAudit(
          taskId: widget.taskId!,
          imageBytes: bytes,
          lang: lang,
        );
        res = Map<String, dynamic>.from(out['audit'] as Map? ?? out);
      } else {
        res = await repo.accessAudit(imageBytes: bytes, lang: lang);
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = res;
      });
      final spoken = res['spoken']?.toString() ?? '';
      if (spoken.isNotEmpty) speakText(spoken, lang: lang);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(humanizeError(e)),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final palette = ZivoPalette.of(context);
    final bottom =
        MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.paddingOf(context).bottom;
    final res = _result;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
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
                const CircleAvatar(
                  backgroundColor: AppColors.brandPurple,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.accessible_forward_rounded),
                ),
                const Gap(12),
                Expanded(
                  child: Text(
                    l.t('tool.audit'),
                    style: AppTextStyles.headingMedium.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context, _result),
                  icon: Icon(Icons.close_rounded, color: palette.textMuted),
                ),
              ],
            ),
            const Gap(8),
            Text(
              l.t('audit.sub'),
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textSecondary,
                height: 1.35,
              ),
            ),
            const Gap(14),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _shoot(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_rounded),
                    label: Text(l.t('eyes.take')),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandPurple,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.brandPurple.withValues(alpha: 0.4),
                      minimumSize: const Size.fromHeight(56),
                    ),
                  ),
                ),
                const Gap(10),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _shoot(ImageSource.gallery),
                    icon: Icon(
                      Icons.photo_library_outlined,
                      color: palette.textPrimary,
                    ),
                    label: Text(
                      l.t('eyes.pick'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.textPrimary,
                      side: BorderSide(color: palette.border, width: 1.4),
                      minimumSize: const Size.fromHeight(56),
                    ),
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const Gap(18),
              Center(
                child: CircularProgressIndicator(color: palette.accent),
              ),
            ],
            if (res != null) ...[
              const Gap(16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.brandPurple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.brandPurple.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      res['spoken']?.toString() ?? '',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 18,
                        height: 1.4,
                        color: palette.textPrimary,
                      ),
                    ),
                    const Gap(10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(
                          context,
                          l.t('audit.stairs'),
                          '${res['stairs'] ?? '—'}',
                        ),
                        _chip(context, l.t('audit.ramp'), '${res['ramp']}'),
                        _chip(context, l.t('audit.door'), '${res['door']}'),
                        _chip(
                          context,
                          l.t('audit.wheelchair'),
                          '${res['wheelchair']}',
                        ),
                      ],
                    ),
                    if ((res['cautions'] as List? ?? const []).isNotEmpty) ...[
                      const Gap(10),
                      Text(
                        '${l.t('eyes.cautions')}: ${(res['cautions'] as List).join(' · ')}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: const Color(0xFFFFB020),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Gap(8),
              FilledButton(
                onPressed: () => Navigator.pop(context, res),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.onAccent,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(l.t('audit.done')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, String value) {
    final palette = ZivoPalette.of(context);
    return Chip(
      label: Text(
        '$label: $value',
        style: TextStyle(color: palette.textPrimary, fontSize: 12),
      ),
      backgroundColor: palette.surface,
      side: BorderSide(color: palette.border),
      visualDensity: VisualDensity.compact,
    );
  }
}
