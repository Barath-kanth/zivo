import 'dart:typed_data';

import 'package:flutter/foundation.dart';

final ValueNotifier<bool> recordingListenable = ValueNotifier<bool>(false);
final ValueNotifier<bool> recordingPausedListenable = ValueNotifier<bool>(false);
final ValueNotifier<List<double>> recordingLevelsListenable =
    ValueNotifier<List<double>>(List<double>.filled(32, 0.08));

bool get isRecording => recordingListenable.value;
bool get isRecordingPaused => recordingPausedListenable.value;

Future<void> startVoiceRecording({
  Duration maxDuration = const Duration(seconds: 30),
}) async {
  recordingListenable.value = true;
  recordingPausedListenable.value = false;
}

Future<void> pauseVoiceRecording() async {
  recordingPausedListenable.value = true;
}

Future<void> resumeVoiceRecording() async {
  recordingPausedListenable.value = false;
}

Future<Uint8List?> stopVoiceRecording() async {
  recordingListenable.value = false;
  recordingPausedListenable.value = false;
  return null;
}

Future<void> cancelVoiceRecording() async {
  recordingListenable.value = false;
  recordingPausedListenable.value = false;
}

Future<Uint8List?> recordVoiceClip({
  Duration maxDuration = const Duration(seconds: 12),
}) async {
  return null;
}
