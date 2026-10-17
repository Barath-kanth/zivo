import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
import 'package:hyperlocal/core/utils/speak_text.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';

/// Doorstep phrases in the three neighbourhood languages. Static on purpose: they work offline,
/// instantly, and are the same words every time. (Native-speaker review recommended.)
const kPhrases = <String, Map<String, String>>{
  'deaf': {
    'en': 'I am deaf. Please write it or show it on my phone, or face me and speak slowly.',
    'si': 'මට ඇසීමේ අපහසුතාවයක් ඇත. කරුණාකර ලියා පෙන්වන්න, නැතහොත් මා දෙස බලා හෙමින් කතා කරන්න.',
    'ta': 'எனக்குக் காது கேட்காது. தயவுசெய்து எழுதிக் காட்டுங்கள், அல்லது என்னைப் பார்த்து மெதுவாகப் பேசுங்கள்.',
  },
  'lowvision': {
    'en': 'I have low vision. Please tell me what each item is as you hand it to me.',
    'si': 'මට පෙනීම අඩුයි. භාණ්ඩ දෙන විට ඒ මොනවාදැයි කියන්න.',
    'ta': 'எனக்கு பார்வை குறைவு. பொருளைக் கொடுக்கும்போது அது என்ன என்று சொல்லுங்கள்.',
  },
  'speech': {
    'en': 'I find speaking difficult. I will type or show my replies. Please give me a moment.',
    'si': 'මට කතා කිරීමට අපහසුයි. මම ටයිප් කර හෝ පෙන්වා පිළිතුරු දෙන්නම්. කරුණාකර ටිකක් ඉඩ දෙන්න.',
    'ta': 'எனக்குப் பேசுவது கடினம். நான் தட்டச்சு செய்து அல்லது காட்டிப் பதிலளிப்பேன். தயவுசெய்து சிறிது நேரம் கொடுங்கள்.',
  },
  'here': {
    'en': 'I am your Zivo helper. I am here for your job.',
    'si': 'මම Zivo උදව්කරුවෙක්. ඔබේ වැඩේ සඳහා පැමිණියා.',
    'ta': 'நான் Zivo உதவியாளர். உங்கள் வேலைக்காக வந்திருக்கிறேன்.',
  },
  'wait': {
    'en': 'One moment, please.',
    'si': 'කරුණාකර විනාඩියක් රැඳී සිටින්න.',
    'ta': 'ஒரு நிமிடம் காத்திருங்கள், தயவுசெய்து.',
  },
  'repeat': {
    'en': 'Please say that again.',
    'si': 'කරුණාකර නැවත කියන්න.',
    'ta': 'மீண்டும் சொல்லுங்கள், தயவுசெய்து.',
  },
  'yes': {'en': 'Yes.', 'si': 'ඔව්.', 'ta': 'ஆம்.'},
  'no': {'en': 'No.', 'si': 'නැත.', 'ta': 'இல்லை.'},
  'done': {
    'en': 'The job is finished. Could you share the End code with me, please?',
    'si': 'වැඩේ අවසන්. කරුණාකර අවසන් කේතය දෙන්න.',
    'ta': 'வேலை முடிந்தது. முடிவுக் குறியீட்டைத் தருவீர்களா?',
  },
  'thanks': {'en': 'Thank you.', 'si': 'ස්තූතියි.', 'ta': 'நன்றி.'},
};

const kLangNames = {'en': 'English', 'si': 'සිංහල', 'ta': 'தமிழ்'};

/// Full-screen, high-contrast card to hold up to someone at the door.
Future<void> showBigCard(BuildContext context, String text) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (ctx) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: InkWell(
        onTap: () => Navigator.pop(ctx),
        child: Semantics(
          label: text,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// "Say it for me": phrase cards + type-to-speak, spoken by Cloud TTS (ta/en) or shown full-screen.
Future<void> showSayIt(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _SayItSheet(),
  );
}

class _SayItSheet extends StatefulWidget {
  const _SayItSheet();

  @override
  State<_SayItSheet> createState() => _SayItSheetState();
}

class _SayItSheetState extends State<_SayItSheet> {
  late String _lang;
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    final c = context.read<LocaleCubit>().code;
    _lang = kLangNames.containsKey(c) ? c : 'en';
  }

  @override
  void dispose() {
    stopSpeaking();
    _text.dispose();
    super.dispose();
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
                backgroundColor: Color(0xFFBE185D),
                foregroundColor: Colors.white,
                child: Icon(Icons.chat_bubble_rounded),
              ),
              const Gap(12),
              Expanded(child: Text(l.t('tool.say'), style: AppTextStyles.headingMedium)),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const Gap(6),
          Row(
            children: [
              Text('${l.t('say.in')}: ', style: AppTextStyles.bodySmall),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in kLangNames.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _lang == e.key,
                      onSelected: (_) => setState(() => _lang = e.key),
                    ),
                ],
              ),
            ],
          ),
          const Gap(8),
          Expanded(
            child: ListView(
              children: [
                for (final entry in kPhrases.entries)
                  _PhraseCard(text: entry.value[_lang]!, lang: _lang),
              ],
            ),
          ),
          const Gap(8),
          TextField(
            controller: _text,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: l.t('say.typeHint'),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: l.t('door.speak'),
                icon: const Icon(Icons.volume_up_rounded),
                onPressed: () {
                  final t = _text.text.trim();
                  if (t.isNotEmpty) speakText(t, lang: _lang);
                },
              ),
            ),
          ),
          const Gap(6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                final t = _text.text.trim();
                if (t.isNotEmpty) showBigCard(context, t);
              },
              icon: const Icon(Icons.fullscreen_rounded),
              label: const Text('Show'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhraseCard extends StatelessWidget {
  const _PhraseCard({required this.text, required this.lang});
  final String text;
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFFDF2F8),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: const Color(0xFFBE185D).withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: AppTextStyles.bodyLarge.copyWith(fontSize: 18, height: 1.4)),
            ),
            Column(
              children: [
                IconButton(
                  tooltip: 'Speak',
                  onPressed: () => speakText(text, lang: lang),
                  icon: const Icon(Icons.volume_up_rounded),
                ),
                IconButton(
                  tooltip: 'Show',
                  onPressed: () => showBigCard(context, text),
                  icon: const Icon(Icons.fullscreen_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Plain-language rewrite of any text (Gemini), for readers who prefer short, simple words.
Future<void> showEasyRead(BuildContext context, {String initialText = ''}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _EasyReadSheet(initialText: initialText),
  );
}

class _EasyReadSheet extends StatefulWidget {
  const _EasyReadSheet({required this.initialText});
  final String initialText;

  @override
  State<_EasyReadSheet> createState() => _EasyReadSheetState();
}

class _EasyReadSheetState extends State<_EasyReadSheet> {
  late final TextEditingController _in;
  bool _busy = false;
  String? _plain;
  List<String> _bullets = const [];

  @override
  void initState() {
    super.initState();
    _in = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final text = _in.text.trim();
    if (text.length < 8) return;
    final lang = context.read<LocaleCubit>().code;
    final repo = context.read<TaskRepository>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final res = await repo.a11ySimplify(text, lang: lang == 'ta' || lang == 'si' ? lang : 'en');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _plain = res['plain']?.toString();
        _bullets = (res['bullets'] as List? ?? const []).map((e) => e.toString()).toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(humanizeError(e)), backgroundColor: AppColors.errorColor),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final bottom = MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.brandPurple,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.short_text_rounded),
                ),
                const Gap(12),
                Expanded(child: Text(l.t('tool.easy'), style: AppTextStyles.headingMedium)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const Gap(10),
            TextField(
              controller: _in,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: l.t('say.easyHint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const Gap(10),
            FilledButton(
              onPressed: _busy ? null : _go,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandPurple,
                minimumSize: const Size.fromHeight(52),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(l.t('say.easyGo')),
            ),
            if (_plain != null) ...[
              const Gap(14),
              Text(_plain!, style: AppTextStyles.bodyLarge.copyWith(fontSize: 19, height: 1.5)),
              for (final b in _bullets)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('• $b', style: AppTextStyles.bodyMedium.copyWith(fontSize: 17, height: 1.4)),
                ),
              TextButton.icon(
                onPressed: () => speakText(_plain!, lang: l.code),
                icon: const Icon(Icons.volume_up_rounded),
                label: Text(l.t('task.read')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
