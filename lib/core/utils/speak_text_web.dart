import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';

/// Optional Cloud TTS hook (returns true if audio was played).
typedef CloudSpeakFn = Future<bool> Function(String text, String lang);

/// Set from [main] to prefer Cloud TTS (ta-IN / en-IN; si bridged).
CloudSpeakFn? cloudSpeakOverride;

/// Shared speaking flag — UI listens so Read ↔ Stop icons stay in sync.
final ValueNotifier<bool> speakingListenable = ValueNotifier<bool>(false);

html.AudioElement? _cloudAudio;

/// Keep utterance referenced so Chrome GC doesn't kill speech mid-flight.
html.SpeechSynthesisUtterance? _activeUtterance;

bool get isSpeaking =>
    speakingListenable.value ||
    (html.window.speechSynthesis?.speaking == true);

Future<List<html.SpeechSynthesisVoice>> _loadVoices(
  html.SpeechSynthesis synth,
) async {
  var voices = synth.getVoices();
  if (voices.isNotEmpty) return voices;

  final done = Completer<void>();
  void onChanged(html.Event _) {
    if (synth.getVoices().isNotEmpty && !done.isCompleted) {
      done.complete();
    }
  }

  synth.addEventListener('voiceschanged', onChanged);
  Timer.periodic(const Duration(milliseconds: 100), (t) {
    if (synth.getVoices().isNotEmpty || t.tick > 20) {
      t.cancel();
      if (!done.isCompleted) done.complete();
    }
  });
  await done.future.timeout(
    const Duration(seconds: 2),
    onTimeout: () {},
  );
  synth.removeEventListener('voiceschanged', onChanged);
  return synth.getVoices();
}

html.SpeechSynthesisVoice? _pickVoice(
  List<html.SpeechSynthesisVoice> voices,
  String lang,
) {
  if (voices.isEmpty) return null;
  final preferred = switch (lang) {
    'ta' => ['ta-IN', 'ta', 'hi-IN', 'en-IN'],
    'si' => ['si-LK', 'si', 'en-IN', 'en-GB'],
    'hi' => ['hi-IN', 'hi', 'en-IN'],
    'es' => ['es-ES', 'es-MX', 'es', 'en-US'],
    'fr' => ['fr-FR', 'fr', 'en-US'],
    'ar' => ['ar-SA', 'ar-EG', 'ar', 'en-US'],
    'zh' => ['zh-CN', 'zh-TW', 'zh', 'en-US'],
    // en-LK is often missing — prefer US/GB/IN first.
    _ => ['en-US', 'en-GB', 'en-IN', 'en-AU', 'en'],
  };
  for (final code in preferred) {
    final lower = code.toLowerCase();
    for (final v in voices) {
      final vl = (v.lang ?? '').toLowerCase();
      if (vl == lower || vl.startsWith('$lower-') || vl.startsWith(lower)) {
        return v;
      }
    }
  }
  for (final v in voices) {
    if ((v.lang ?? '').toLowerCase().startsWith('en')) return v;
  }
  return voices.first;
}

Future<void> speakText(
  String text, {
  String lang = 'en',
  void Function()? onDone,
}) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    onDone?.call();
    return;
  }

  stopSpeaking();
  await Future<void>.delayed(const Duration(milliseconds: 80));

  // Prefer Cloud TTS for Tamil / Sinhala (browser synth is unreliable).
  if (cloudSpeakOverride != null && (lang == 'ta' || lang == 'si' || lang == 'en')) {
    try {
      speakingListenable.value = true;
      final ok = await cloudSpeakOverride!(trimmed, lang);
      if (ok) {
        speakingListenable.value = false;
        onDone?.call();
        return;
      }
    } catch (_) {
      /* fall through to browser synth */
    }
    speakingListenable.value = false;
  }

  final synth = html.window.speechSynthesis;
  if (synth == null) {
    onDone?.call();
    return;
  }

  // Chrome quirk: cancel() then immediate speak() often produces silence.
  synth.cancel();
  _activeUtterance = null;
  speakingListenable.value = false;
  await Future<void>.delayed(const Duration(milliseconds: 150));

  final voices = await _loadVoices(synth);
  final voice = _pickVoice(voices, lang);

  final u = html.SpeechSynthesisUtterance(trimmed);
  _activeUtterance = u;
  if (voice != null) {
    u.voice = voice;
    u.lang = voice.lang ?? 'en-US';
  } else {
    u.lang = switch (lang) {
      'ta' => 'ta-IN',
      'si' => 'si-LK',
      'hi' => 'hi-IN',
      'es' => 'es-ES',
      'fr' => 'fr-FR',
      'ar' => 'ar-SA',
      'zh' => 'zh-CN',
      _ => 'en-US',
    };
  }
  u.rate = 0.95;
  u.pitch = 1.0;
  u.volume = 1.0;

  var finished = false;
  void finish([_]) {
    if (finished) return;
    finished = true;
    if (identical(_activeUtterance, u)) {
      _activeUtterance = null;
    }
    speakingListenable.value = false;
    onDone?.call();
  }

  u.onEnd.listen(finish);
  u.onError.listen(finish);

  speakingListenable.value = true;
  synth.speak(u);

  // Chrome sometimes parks the queue as paused after tab backgrounding.
  await Future<void>.delayed(const Duration(milliseconds: 80));
  if (synth.paused == true) {
    synth.resume();
  }
  // Re-assert speaking flag if synth reports it.
  if (synth.speaking == true) {
    speakingListenable.value = true;
  }
}

void stopSpeaking() {
  speakingListenable.value = false;
  _activeUtterance = null;
  html.window.speechSynthesis?.cancel();
  try {
    _cloudAudio?.pause();
    _cloudAudio?.remove();
  } catch (_) {
    /* ignore */
  }
  _cloudAudio = null;
}

/// Play base64 MP3 from Cloud TTS; used by [cloudSpeakOverride].
Future<bool> playCloudMp3Base64(String b64) async {
  final done = Completer<void>();
  try {
    _cloudAudio?.pause();
    _cloudAudio?.remove();
  } catch (_) {}
  final audio = html.AudioElement()
    ..src = 'data:audio/mpeg;base64,$b64'
    ..autoplay = true;
  _cloudAudio = audio;
  html.document.body?.append(audio);
  void finish([_]) {
    if (!done.isCompleted) done.complete();
    audio.remove();
    if (identical(_cloudAudio, audio)) _cloudAudio = null;
  }

  audio.onEnded.listen(finish);
  audio.onError.listen(finish);
  try {
    await audio.play();
  } catch (_) {
    finish();
    return false;
  }
  await done.future.timeout(
    const Duration(seconds: 60),
    onTimeout: () {},
  );
  return true;
}

/// Decode Cloud TTS JSON `{audio_base64}` helper for callers.
String? audioBase64FromTtsResponse(Map<String, dynamic> res) {
  final v = res['audio_base64'];
  if (v is String && v.isNotEmpty) return v;
  return null;
}
