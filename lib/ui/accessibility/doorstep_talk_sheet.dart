import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
import 'package:hyperlocal/core/utils/speak_text.dart';
import 'package:hyperlocal/core/utils/voice_recorder.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/ui/accessibility/say_it_sheet.dart';
import 'package:hyperlocal/ui/accessibility/zivo_eyes_sheet.dart' show aiLang;

/// Doorstep Talk — a two-way conversation for deaf / hard-of-hearing helpers.
/// Tap, the other person speaks (Tamil, Sinhala or English), and it appears as large text in
/// the helper's language. The helper answers by phrase card, typing (spoken aloud) or full-screen text.
Future<void> showDoorstepTalk(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _DoorstepSheet(),
  );
}

class _Line {
  _Line({required this.text, required this.original, required this.lang, required this.fromOther});
  final String text;
  final String original;
  final String lang;
  final bool fromOther;
}

class _DoorstepSheet extends StatefulWidget {
  const _DoorstepSheet();

  @override
  State<_DoorstepSheet> createState() => _DoorstepSheetState();
}

class _DoorstepSheetState extends State<_DoorstepSheet> {
  final _lines = <_Line>[];
  final _reply = TextEditingController();
  bool _listening = false;
  bool _busy = false;
  late String _replyLang;

  @override
  void initState() {
    super.initState();
    final c = context.read<LocaleCubit>().code;
    _replyLang = kLangNames.containsKey(c) ? c : 'en';
  }

  @override
  void dispose() {
    if (recordingListenable.value) cancelVoiceRecording();
    stopSpeaking();
    _reply.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final l = context.read<LocaleCubit>();
    final repo = context.read<TaskRepository>();
    final lang = aiLang(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!_listening) {
      try {
        await startVoiceRecording(maxDuration: const Duration(seconds: 20));
        if (mounted) setState(() => _listening = true);
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(humanizeError(e)), backgroundColor: AppColors.errorColor),
        );
      }
      return;
    }
    setState(() {
      _listening = false;
      _busy = true;
    });
    try {
      final clip = await stopVoiceRecording();
      if (clip == null || clip.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final res = await repo.doorstepTalk(audioBytes: clip, lang: lang);
      if (!mounted) return;
      final heard = res['heard']?.toString().trim() ?? '';
      setState(() {
        _busy = false;
        if (heard.isEmpty) {
          messenger.showSnackBar(SnackBar(content: Text(l.t('door.nothing'))));
        } else {
          _lines.insert(
            0,
            _Line(
              text: res['for_reader']?.toString().trim().isNotEmpty == true
                  ? res['for_reader'].toString()
                  : heard,
              original: heard,
              lang: res['heard_lang']?.toString() ?? '',
              fromOther: true,
            ),
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(humanizeError(e)), backgroundColor: AppColors.errorColor),
      );
    }
  }

  void _say(String text) {
    if (text.trim().isEmpty) return;
    speakText(text, lang: _replyLang);
    setState(() => _lines.insert(0, _Line(text: text, original: text, lang: _replyLang, fromOther: false)));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final bottom = MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 16 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFF1D4ED8),
                foregroundColor: Colors.white,
                child: Icon(Icons.hearing_rounded),
              ),
              const Gap(12),
              Expanded(child: Text(l.t('tool.doorstep'), style: AppTextStyles.headingMedium)),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const Gap(10),
          Expanded(
            child: _lines.isEmpty
                ? Center(
                    child: Text(
                      l.t('door.hint'),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted),
                    ),
                  )
                : ListView.builder(
                    reverse: false,
                    itemCount: _lines.length,
                    itemBuilder: (_, i) {
                      final m = _lines[i];
                      return Align(
                        alignment: m.fromOther ? Alignment.centerLeft : Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          constraints: const BoxConstraints(maxWidth: 520),
                          decoration: BoxDecoration(
                            color: m.fromOther ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                m.text,
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontSize: 26,
                                  height: 1.35,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (m.fromOther && m.original != m.text)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    m.original,
                                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Gap(6),
          // Big listen button: the primary action.
          Semantics(
            button: true,
            label: _listening ? l.t('door.stop') : l.t('door.tap'),
            child: FilledButton.icon(
              onPressed: _busy ? null : _toggle,
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, size: 28),
              label: Text(
                _busy
                    ? l.t('door.thinking')
                    : (_listening ? '${l.t('door.listening')}  ·  ${l.t('door.stop')}' : l.t('door.tap')),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _listening ? AppColors.errorColor : const Color(0xFF1D4ED8),
                minimumSize: const Size.fromHeight(66),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const Gap(10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final k in const ['yes', 'no', 'wait', 'repeat', 'thanks'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(kPhrases[k]![_replyLang]!),
                      onPressed: () => _say(kPhrases[k]![_replyLang]!),
                    ),
                  ),
              ],
            ),
          ),
          const Gap(8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _reply,
                  decoration: InputDecoration(
                    hintText: l.t('door.reply'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (v) {
                    _say(v);
                    _reply.clear();
                  },
                ),
              ),
              const Gap(8),
              PopupMenuButton<String>(
                tooltip: l.t('say.in'),
                initialValue: _replyLang,
                onSelected: (v) => setState(() => _replyLang = v),
                itemBuilder: (_) => [
                  for (final e in kLangNames.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
                ],
                child: Chip(label: Text(kLangNames[_replyLang]!)),
              ),
              IconButton.filled(
                tooltip: l.t('door.speak'),
                onPressed: () {
                  _say(_reply.text);
                  _reply.clear();
                },
                icon: const Icon(Icons.volume_up_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
