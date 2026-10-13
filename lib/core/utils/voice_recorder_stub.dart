import 'dart:typed_data';

import 'package:flutter/foundation.dart';

final ValueNotifier<bool> recordingListenable = ValueNotifier<bool>(false);

bool get isRecording => recordingListenable.value;

Future<void> startVoiceRecording({
  Duration maxDuration = const Duration(seconds: 30),
}) async {
  recordingListenable.value = true;
}

Future<Uint8List?> stopVoiceRecording() async {
  recordingListenable.value = false;
  return null;
}

Future<void> cancelVoiceRecording() async {
  recordingListenable.value = false;
}

Future<Uint8List?> recordVoiceClip({
  Duration maxDuration = const Duration(seconds: 12),
}) async {
  return null;
}
