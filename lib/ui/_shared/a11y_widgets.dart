import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/blocs/a11y/a11y_cubit.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
import 'package:hyperlocal/core/utils/speak_text.dart';
import 'package:hyperlocal/core/utils/voice_recorder.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/ui/_shared/a11y_voice_assist.dart';
import 'package:image_picker/image_picker.dart';

/// Compact Read aloud control — icon toggles Read ↔ Stop with global sync.
/// Uses the app [LocaleCubit] language when [lang] is omitted.
class A11yReadButton extends StatefulWidget {
  const A11yReadButton({
    super.key,
    required this.text,
    this.lang,
    this.compact = true,
    this.iconOnly = false,
  });

  final String text;
  final String? lang;
  final bool compact;
  final bool iconOnly;

  @override
  State<A11yReadButton> createState() => _A11yReadButtonState();
}

class _A11yReadButtonState extends State<A11yReadButton> {
  @override
  void initState() {
    super.initState();
    speakingListenable.addListener(_onSpeakingChanged);
  }

  @override
  void dispose() {
    speakingListenable.removeListener(_onSpeakingChanged);
    super.dispose();
  }

  void _onSpeakingChanged() {
    if (mounted) setState(() {});
  }

  String get _lang {
    if (widget.lang != null && widget.lang!.isNotEmpty) return widget.lang!;
    try {
      return context.read<LocaleCubit>().code;
    } catch (_) {
      return 'en';
    }
  }

  Future<void> _toggle() async {
    if (widget.text.trim().isEmpty) return;
    if (speakingListenable.value || isSpeaking) {
      stopSpeaking();
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    // Resume AudioContext on user gesture (Chrome autoplay policy).
    await speakText(widget.text, lang: _lang);
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    if (!speakingListenable.value && !isSpeaking) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No voice available in this browser. Allow sound for this site, or try Chrome.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Read aloud only when Accessibility Mode is on.
    var a11yOn = false;
    try {
      a11yOn = context.watch<A11yCubit>().state;
    } catch (_) {
      a11yOn = false;
    }
    if (!a11yOn) return const SizedBox.shrink();

    final speaking = speakingListenable.value;
    final size = widget.compact ? 18.0 : 20.0;
    String readLabel = 'Read';
    String stopLabel = 'Stop';
    try {
      final l = context.watch<LocaleCubit>();
      readLabel = l.t('task.read');
      stopLabel = l.t('task.stop');
    } catch (_) {}

    if (widget.iconOnly) {
      return IconButton(
        tooltip: speaking ? stopLabel : readLabel,
        onPressed: widget.text.trim().isEmpty ? null : _toggle,
        icon: Icon(
          speaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
          size: size,
          color: speaking ? AppColors.errorColor : AppColors.helperAccent,
        ),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      );
    }

    return TextButton.icon(
      onPressed: widget.text.trim().isEmpty ? null : _toggle,
      icon: Icon(
        speaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
        size: size,
      ),
      label: Text(speaking ? stopLabel : readLabel),
      style: TextButton.styleFrom(
        foregroundColor:
            speaking ? AppColors.errorColor : AppColors.helperAccent,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        visualDensity: VisualDensity.compact,
        // Avoid Flutter-web underline artifacts under Tamil glyphs.
        textStyle: const TextStyle(decoration: TextDecoration.none),
      ),
    );
  }
}

/// Compact Accessibility Mode toggle + Read for auth / pre-shell screens.
class A11yAuthBar extends StatelessWidget {
  const A11yAuthBar({
    super.key,
    required this.readText,
    this.hint = 'Zivo sign-in screen',
  });

  final String readText;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<A11yCubit, bool>(
      builder: (context, on) {
        return Material(
          color: on
              ? AppColors.helperAccent.withValues(alpha: 0.12)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.accessibility_new_rounded,
                  size: 18,
                  color: on ? AppColors.helperAccent : AppColors.textMuted,
                ),
                const Gap(6),
                Expanded(
                  child: Text(
                    on ? 'Accessibility on' : 'Accessibility',
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => showA11yVoiceAssist(context),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    foregroundColor: AppColors.helperAccent,
                  ),
                  child: const Text('Speak'),
                ),
                if (on) ...[
                  A11yReadButton(text: readText),
                  TextButton(
                    onPressed: () => showA11yDescribeSheet(
                      context,
                      hint: hint,
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text('Describe'),
                  ),
                ],
                Switch.adaptive(
                  value: on,
                  onChanged: (v) => context.read<A11yCubit>().setEnabled(v),
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.helperAccent,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Simplify long copy via Gemini plain-language endpoint.
class A11ySimplifyButton extends StatelessWidget {
  const A11ySimplifyButton({
    super.key,
    required this.text,
    required this.onSimplified,
  });

  final String text;
  final void Function(String plain, List<String> bullets) onSimplified;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: text.trim().length < 8
          ? null
          : () async {
              try {
                final res =
                    await context.read<TaskRepository>().a11ySimplify(text);
                final plain = res['plain']?.toString() ?? text;
                final bullets = (res['bullets'] as List?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    const <String>[];
                onSimplified(plain, bullets);
                final a11y = context.read<A11yCubit>().enabled;
                if (a11y) speakText(plain);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(humanizeError(e)),
                    backgroundColor: AppColors.errorColor,
                  ),
                );
              }
            },
      icon: const Icon(Icons.short_text_rounded, size: 16),
      label: const Text('Simplify'),
      style: TextButton.styleFrom(
        foregroundColor: Colors.black87,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Describe this screen — speaks immediately (no folder picker).
/// Optional photo attach is a secondary action inside the results sheet.
Future<void> showA11yDescribeSheet(
  BuildContext context, {
  String hint = 'Zivo app screen',
  bool preferCamera = false,
  bool allowPhoto = false,
}) async {
  // Toggle: second tap / banner Stop cancels speech.
  if (speakingListenable.value || isSpeaking) {
    stopSpeaking();
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Describing — reading aloud…'),
      duration: Duration(seconds: 2),
    ),
  );

  // Speak under the user gesture so Chrome allows TTS (no gallery first).
  await speakText('Describing this screen.');

  try {
    List<int>? bytes;
    // Only open camera/gallery when explicitly requested — never by default.
    if (allowPhoto || preferCamera) {
      try {
        final file = await ImagePicker().pickImage(
          source: preferCamera ? ImageSource.camera : ImageSource.gallery,
          imageQuality: 70,
          maxWidth: 1280,
        );
        if (file != null) bytes = await file.readAsBytes();
      } catch (_) {
        /* photo optional */
      }
    }

    if (!context.mounted) return;
    final res = await context.read<TaskRepository>().a11yDescribe(
          imageBytes: bytes,
          hint: hint,
        );
    if (!context.mounted) return;
    final summary = res['summary']?.toString() ?? '';
    final actions = (res['focus_actions'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];

    final spoken = [
      if (summary.isNotEmpty) summary,
      if (actions.isNotEmpty) 'Next steps: ${actions.join('. ')}',
    ].join(' ');

    if (spoken.isNotEmpty) {
      await speakText(spoken);
    }

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            20 + MediaQuery.paddingOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Describe this', style: AppTextStyles.headingMedium),
              const Gap(4),
              Text(
                'Spoken scene description for blind and low-vision users.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const Gap(12),
              Text(
                summary.isEmpty ? 'No description returned.' : summary,
                style: AppTextStyles.bodyMedium.copyWith(height: 1.4),
              ),
              if (actions.isNotEmpty) ...[
                const Gap(12),
                Text('Next steps', style: AppTextStyles.headingSmall),
                const Gap(6),
                ...actions.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $a', style: AppTextStyles.bodySmall),
                  ),
                ),
              ],
              const Gap(12),
              Row(
                children: [
                  A11yReadButton(text: spoken.isEmpty ? summary : spoken),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      showA11yDescribeSheet(
                        context,
                        hint: hint,
                        preferCamera: true,
                        allowPhoto: true,
                      );
                    },
                    icon: const Icon(Icons.photo_camera_outlined, size: 16),
                    label: const Text('Use photo'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      stopSpeaking();
                      Navigator.pop(ctx);
                    },
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  } catch (e) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(humanizeError(e)),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }
}

/// Record voice → caption text (for chat).
Future<String?> captureA11yCaption(
  BuildContext context, {
  String lang = 'en',
}) async {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Listening 10s for caption…'),
      duration: Duration(seconds: 10),
    ),
  );
  try {
    final clip = await recordVoiceClip(
      maxDuration: const Duration(seconds: 10),
    );
    if (!context.mounted) return null;
    final res = await context.read<TaskRepository>().a11yTranscribe(
          audioBytes: clip,
          lang: lang,
        );
    return res['transcript']?.toString().trim();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanizeError(e)),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
    return null;
  }
}
