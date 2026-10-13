import 'package:flutter/foundation.dart';

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
