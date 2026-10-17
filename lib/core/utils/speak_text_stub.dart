import 'package:flutter/foundation.dart';

typedef CloudSpeakFn = Future<bool> Function(String text, String lang);

CloudSpeakFn? cloudSpeakOverride;

final ValueNotifier<bool> speakingListenable = ValueNotifier<bool>(false);

bool get isSpeaking => speakingListenable.value;

Future<void> speakText(
  String text, {
  String lang = 'en',
  void Function()? onDone,
}) async {
  speakingListenable.value = false;
  onDone?.call();
}

void stopSpeaking() {
  speakingListenable.value = false;
}

Future<bool> playCloudMp3Base64(String b64) async => false;

String? audioBase64FromTtsResponse(Map<String, dynamic> res) {
  final v = res['audio_base64'];
  if (v is String && v.isNotEmpty) return v;
  return null;
}
