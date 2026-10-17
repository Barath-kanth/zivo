import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
import 'package:hyperlocal/core/utils/speak_text.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/auth/auth_state.dart';
import 'package:hyperlocal/core/services/location_service.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/models/task_status.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:image_picker/image_picker.dart';

/// Server understands en / ta / si; any other app language falls back to English.
String aiLang(BuildContext context) {
  final c = context.read<LocaleCubit>().code;
  return (c == 'ta' || c == 'si') ? c : 'en';
}

/// Zivo Eyes — point the camera, hear what it sees. Built for blind and low-vision helpers.
/// Gemini vision describes the scene, reads text, or checks items against a shopping list.
Future<void> showZivoEyes(BuildContext context, {List<String> initialItems = const []}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _ZivoEyesSheet(initialItems: initialItems),
  );
}

class _ZivoEyesSheet extends StatefulWidget {
  const _ZivoEyesSheet({required this.initialItems});
  final List<String> initialItems;

  @override
  State<_ZivoEyesSheet> createState() => _ZivoEyesSheetState();
}

class _ZivoEyesSheetState extends State<_ZivoEyesSheet> {
  String _mode = 'describe';
  bool _busy = false;
  Map<String, dynamic>? _result;
  late final TextEditingController _list;

  @override
  void initState() {
    super.initState();
    _list = TextEditingController(text: widget.initialItems.join('\n'));
  }

  @override
  void dispose() {
    stopSpeaking();
    _list.dispose();
    super.dispose();
  }

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
      // Immediate audio feedback so a blind user knows it is working.
      speakText(l.t('eyes.working'), lang: l.code);
      final items = _mode == 'match'
          ? _list.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
          : <String>[];
      final res = await repo.zivoEyes(
        imageBytes: bytes,
        mode: _mode,
        lang: lang,
        items: items,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = res;
      });
      final spoken = _spokenSummary(res, l);
      if (spoken.isNotEmpty) speakText(spoken, lang: lang);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(humanizeError(e)), backgroundColor: AppColors.errorColor),
      );
    }
  }

  String _spokenSummary(Map<String, dynamic> res, LocaleCubit l) {
    final parts = <String>[res['spoken']?.toString() ?? ''];
    final matches = res['matches'] as List? ?? const [];
    for (final m in matches) {
      if (m is! Map) continue;
      final v = switch (m['verdict']) {
        'yes' => l.t('eyes.yes'),
        'no' => l.t('eyes.no'),
        _ => l.t('eyes.unsure'),
      };
      parts.add('${m['item']}: $v. ${m['note'] ?? ''}');
    }
    final cautions = (res['cautions'] as List? ?? const []).map((e) => e.toString()).toList();
    if (cautions.isNotEmpty) parts.add('${l.t('eyes.cautions')}: ${cautions.join('. ')}');
    return parts.where((s) => s.trim().isNotEmpty).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final bottom = MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom;
    final res = _result;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  child: Icon(Icons.photo_camera_rounded),
                ),
                const Gap(12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(l.t('tool.eyes'), style: AppTextStyles.headingMedium),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const Gap(10),
            Wrap(
              spacing: 8,
              children: [
                for (final m in const ['describe', 'read', 'match'])
                  ChoiceChip(
                    label: Text(l.t('eyes.$m')),
                    selected: _mode == m,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onSelected: (_) => setState(() => _mode = m),
                  ),
              ],
            ),
            if (_mode == 'match') ...[
              const Gap(10),
              TextField(
                controller: _list,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: l.t('eyes.listHint'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const Gap(14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _shoot(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_rounded),
                    label: Text(l.t('eyes.take')),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      minimumSize: const Size.fromHeight(60),
                      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const Gap(10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _shoot(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(l.t('eyes.pick')),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 60)),
                ),
              ],
            ),
            const Gap(10),
            Text(
              l.t('eyes.hint'),
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted, height: 1.35),
            ),
            if (_busy) ...[
              const Gap(18),
              Center(
                child: Semantics(
                  liveRegion: true,
                  label: l.t('eyes.working'),
                  child: const CircularProgressIndicator(),
                ),
              ),
            ],
            if (res != null) ...[
              const Gap(16),
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F8F6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        res['spoken']?.toString() ?? '',
                        style: AppTextStyles.bodyLarge.copyWith(fontSize: 20, height: 1.45),
                      ),
                      for (final m in (res['matches'] as List? ?? const []))
                        if (m is Map)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  switch (m['verdict']) {
                                    'yes' => Icons.check_circle_rounded,
                                    'no' => Icons.cancel_rounded,
                                    _ => Icons.help_rounded,
                                  },
                                  color: switch (m['verdict']) {
                                    'yes' => const Color(0xFF15803D),
                                    'no' => AppColors.errorColor,
                                    _ => const Color(0xFFB54708),
                                  },
                                ),
                                const Gap(8),
                                Expanded(
                                  child: Text(
                                    '${m['item']} — ${m['note'] ?? ''}',
                                    style: AppTextStyles.bodyMedium.copyWith(height: 1.35),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      if ((res['cautions'] as List? ?? const []).isNotEmpty) ...[
                        const Gap(12),
                        Text(
                          '${l.t('eyes.cautions')}: ${(res['cautions'] as List).join(' · ')}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: const Color(0xFFB54708),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Gap(8),
              TextButton.icon(
                onPressed: () => speakText(_spokenSummary(res, l), lang: aiLang(context)),
                icon: const Icon(Icons.volume_up_rounded),
                label: Text(l.t('task.read')),
              ),
              if (_needsSightedAssist(res)) ...[
                const Gap(4),
                Text(
                  l.t('eyes.assistSub'),
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
                ),
                const Gap(6),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _requestSightedAssist(res),
                  icon: const Icon(Icons.visibility_rounded),
                  label: Text(l.t('eyes.assist')),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  bool _needsSightedAssist(Map<String, dynamic> res) {
    final matches = res['matches'] as List? ?? const [];
    final unsure = matches.any((m) => m is Map && m['verdict'] == 'unsure');
    final cautions = (res['cautions'] as List? ?? const []).isNotEmpty;
    final spoken = (res['spoken']?.toString() ?? '').toLowerCase();
    final soft = spoken.contains("can't tell") ||
        spoken.contains('cannot tell') ||
        spoken.contains('not sure') ||
        spoken.contains('unsure');
    return unsure || cautions || soft;
  }

  Future<void> _requestSightedAssist(Map<String, dynamic> res) async {
    final l = context.read<LocaleCubit>();
    final repo = context.read<TaskRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) {
      messenger.showSnackBar(const SnackBar(content: Text('Please sign in first')));
      return;
    }
    setState(() => _busy = true);
    try {
      final pos = await LocationService.getCurrentPosition();
      final lat = pos?.latitude ?? 6.9271;
      final lon = pos?.longitude ?? 79.8612;
      final spoken = res['spoken']?.toString() ?? '';
      final task = Task(
        id: '',
        clientId: auth.profile.id,
        title: 'Sighted assist — 60 second check',
        description:
            'A blind neighbour needs a short video check. Please call or video-chat and confirm what they are holding.\n\nZivo Eyes said: $spoken',
        category: TaskCategory.sightedAssist,
        estimatedHours: 0.1,
        hourlyRate: 500,
        totalAmount: 200,
        location: LatLng(lat, lon),
        status: TaskStatus.open,
        createdAt: DateTime.now(),
      );
      await repo.createTask(task, urgency: 'urgent');
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(l.t('eyes.assistPosted'))));
      speakText(l.t('eyes.assistPosted'), lang: aiLang(context));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(humanizeError(e)), backgroundColor: AppColors.errorColor),
      );
    }
  }
}
