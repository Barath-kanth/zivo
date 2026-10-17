import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/blocs/ability/ability_cubit.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
import 'package:hyperlocal/core/utils/speak_text.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/ui/accessibility/doorstep_talk_sheet.dart';
import 'package:hyperlocal/ui/accessibility/say_it_sheet.dart';
import 'package:hyperlocal/ui/accessibility/zivo_eyes_sheet.dart';

/// Helper side: "does this job fit how I work?" (deterministic table) + "Adapt this job for me"
/// (Gemini writes a step-by-step brief that names the Zivo tool for each step).
/// Renders nothing unless the helper has an ability profile.
class AbilityJobCard extends StatefulWidget {
  const AbilityJobCard({super.key, required this.taskId, this.shoppingItems = const []});

  final String taskId;
  final List<String> shoppingItems;

  @override
  State<AbilityJobCard> createState() => _AbilityJobCardState();
}

class _AbilityJobCardState extends State<AbilityJobCard> {
  Map<String, dynamic>? _fit;
  Map<String, dynamic>? _brief;
  bool _loadingBrief = false;

  @override
  void initState() {
    super.initState();
    _loadFit();
  }

  Future<void> _loadFit() async {
    if (context.read<AbilityCubit>().state.isEmpty) return;
    try {
      final res = await context.read<TaskRepository>().abilityFit(widget.taskId);
      if (!mounted) return;
      setState(() => _fit = Map<String, dynamic>.from(res['fit'] as Map));
    } catch (_) {
      /* the card is advisory; stay hidden on error */
    }
  }

  Future<void> _adapt() async {
    final repo = context.read<TaskRepository>();
    final lang = aiLang(context);
    final messenger = ScaffoldMessenger.of(context);
    final visual = context.read<AbilityCubit>().state.has('visual');
    setState(() => _loadingBrief = true);
    try {
      final res = await repo.adaptBrief(widget.taskId, lang: lang);
      if (!mounted) return;
      setState(() {
        _loadingBrief = false;
        _brief = res;
      });
      if (visual) {
        final steps = (res['steps'] as List? ?? const [])
            .whereType<Map>()
            .map((s) => s['text'].toString())
            .toList();
        speakText(steps.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join(' '), lang: lang);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingBrief = false);
      messenger.showSnackBar(
        SnackBar(content: Text(humanizeError(e)), backgroundColor: AppColors.errorColor),
      );
    }
  }

  void _openTool(String tool) {
    switch (tool) {
      case 'eyes':
        showZivoEyes(context, initialItems: widget.shoppingItems);
      case 'doorstep':
        showDoorstepTalk(context);
      case 'say':
        showSayIt(context);
      case 'easyread':
        showEasyRead(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final profile = context.watch<AbilityCubit>().state;
    final fit = _fit;
    if (profile.isEmpty || fit == null) return const SizedBox.shrink();
    final level = fit['level']?.toString() ?? 'great';
    final concerns = (fit['concerns'] as List? ?? const []).whereType<Map>().toList();
    final color = switch (level) {
      'great' => const Color(0xFF15803D),
      'adaptable' => const Color(0xFF0F766E),
      _ => const Color(0xFFB54708),
    };
    final steps = (_brief?['steps'] as List? ?? const []).whereType<Map>().toList();
    final headsUp = _brief?['heads_up']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                level == 'heads_up' ? Icons.warning_amber_rounded : Icons.verified_rounded,
                color: color,
              ),
              const Gap(8),
              Expanded(
                child: Text(
                  l.t('fit.$level'),
                  style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w800, color: color),
                ),
              ),
            ],
          ),
          for (final c in concerns)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '• ${l.t('fit.tip.${c['tip']}')}',
                style: AppTextStyles.bodySmall.copyWith(height: 1.35),
              ),
            ),
          const Gap(6),
          Text(
            l.t('fit.note'),
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted, fontSize: 11.5),
          ),
          const Gap(10),
          if (steps.isEmpty)
            FilledButton.icon(
              onPressed: _loadingBrief ? null : _adapt,
              icon: _loadingBrief
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_loadingBrief ? l.t('brief.working') : l.t('brief.btn')),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.black,
                minimumSize: const Size.fromHeight(50),
              ),
            )
          else ...[
            Text(l.t('brief.title'), style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w800)),
            const Gap(6),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}. ', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w800)),
                    Expanded(
                      child: Text(
                        steps[i]['text'].toString(),
                        style: AppTextStyles.bodyMedium.copyWith(height: 1.4),
                      ),
                    ),
                    if (steps[i]['tool'] != 'none')
                      IconButton(
                        tooltip: steps[i]['tool'].toString(),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _openTool(steps[i]['tool'].toString()),
                        icon: Icon(switch (steps[i]['tool']) {
                          'eyes' => Icons.photo_camera_rounded,
                          'doorstep' => Icons.hearing_rounded,
                          'say' => Icons.chat_bubble_rounded,
                          _ => Icons.short_text_rounded,
                        }),
                      ),
                  ],
                ),
              ),
            if (headsUp.isNotEmpty)
              Text(
                headsUp,
                style: AppTextStyles.bodySmall.copyWith(
                  color: const Color(0xFFB54708),
                  fontWeight: FontWeight.w700,
                ),
              ),
            TextButton.icon(
              onPressed: () => speakText(
                steps.asMap().entries.map((e) => '${e.key + 1}. ${e.value['text']}').join(' '),
                lang: aiLang(context),
              ),
              icon: const Icon(Icons.volume_up_rounded),
              label: Text(l.t('task.read')),
            ),
          ],
        ],
      ),
    );
  }
}

/// Entrance access audit shown to helpers (and the client) — stairs, ramp, door.
class AccessAuditCard extends StatelessWidget {
  const AccessAuditCard({super.key, required this.task, this.onAdd});

  final Task task;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final audit = task.accessAudit;
    if (audit == null || audit.isEmpty) {
      if (onAdd == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.accessible_forward_rounded),
          label: Text(l.t('tool.audit')),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandPurple.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('audit.cardTitle'), style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w800)),
          const Gap(6),
          Text(audit['spoken']?.toString() ?? '', style: AppTextStyles.bodyMedium.copyWith(height: 1.4)),
          const Gap(8),
          Text(
            '${l.t('audit.stairs')}: ${audit['stairs'] ?? '—'} · ${l.t('audit.ramp')}: ${audit['ramp']} · ${l.t('audit.door')}: ${audit['door']} · ${l.t('audit.wheelchair')}: ${audit['wheelchair']}',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Client side: the helper chose to share an access note. The client can keep them or choose
/// someone else (the job reopens; money stays in escrow). Only shown before the job starts.
class AccessNoteCard extends StatelessWidget {
  const AccessNoteCard({super.key, required this.task, required this.onChanged});

  final Task task;

  /// Called after the client chose someone else, so the screen can refresh.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final raw = task.helperProfile?['access'];
    if (raw is! Map) return const SizedBox.shrink();
    final l = context.watch<LocaleCubit>();
    final abilities = (raw['abilities'] as List? ?? const []).map((e) => e.toString()).toList();
    if (abilities.isEmpty) return const SizedBox.shrink();
    final note = raw['note']?.toString().trim() ?? '';
    final name = task.helperDisplayName ?? '';
    final tips = [
      for (final a in abilities)
        if (const {'visual', 'hearing', 'speech', 'mobility', 'cognitive'}.contains(a))
          l.t('acc.tip${a[0].toUpperCase()}${a.substring(1)}'),
    ];
    final canChange = task.status.name == 'matched';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1D4ED8).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.accessibility_new_rounded, color: Color(0xFF1D4ED8)),
              const Gap(8),
              Expanded(
                child: Text(
                  l.t('acc.title').replaceAll('{name}', name),
                  style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const Gap(6),
          Text(
            l
                .t('acc.body')
                .replaceAll('{abilities}', abilities.map((a) => l.t('acc.$a')).join(', ')),
            style: AppTextStyles.bodyMedium.copyWith(height: 1.4),
          ),
          if (note.isNotEmpty) ...[
            const Gap(6),
            Text('“$note”', style: AppTextStyles.bodyMedium.copyWith(fontStyle: FontStyle.italic, height: 1.4)),
          ],
          for (final t in tips)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(t, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted)),
            ),
          if (canChange) ...[
            const Gap(10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final repo = context.read<TaskRepository>();
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await repo.declineHelper(task.id, reason: 'access note');
                        messenger.showSnackBar(SnackBar(content: Text(l.t('acc.changed'))));
                        onChanged();
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(humanizeError(e)), backgroundColor: AppColors.errorColor),
                        );
                      }
                    },
                    child: Text(l.t('acc.change')),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
