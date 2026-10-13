import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Global recording flag — UI shows Start ↔ Stop Recording.
final ValueNotifier<bool> recordingListenable = ValueNotifier<bool>(false);

html.MediaRecorder? _recorder;
html.MediaStream? _stream;
final List<html.Blob> _chunks = [];
Completer<Uint8List?>? _stopped;
Timer? _maxTimer;

bool get isRecording => recordingListenable.value;

Future<void> startVoiceRecording({
  Duration maxDuration = const Duration(seconds: 30),
}) async {
  if (recordingListenable.value) return;

  final devices = html.window.navigator.mediaDevices;
  if (devices == null) {
    throw StateError(
      'Microphone not available in this browser. Use Chrome and allow mic access.',
    );
  }

  try {
    _stream = await devices.getUserMedia({'audio': true});
  } catch (e) {
    final msg = e.toString();
    if (msg.contains('NotAllowedError') ||
        msg.contains('Permission dismissed') ||
        msg.contains('NotAllowed') ||
        msg.contains('PermissionDenied')) {
      throw StateError(
        'Microphone permission blocked. Click the lock icon in the address bar → allow Microphone for this site, then tap Start recording again.',
      );
    }
    if (msg.contains('NotFoundError')) {
      throw StateError('No microphone found on this device.');
    }
    rethrow;
  }

  _chunks.clear();
  final mime = html.MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
      ? 'audio/webm;codecs=opus'
      : 'audio/webm';
  final recorder = html.MediaRecorder(_stream!, {'mimeType': mime});
  _recorder = recorder;
  _stopped = Completer<Uint8List?>();

  recorder.addEventListener('dataavailable', (html.Event e) {
    final me = e as html.BlobEvent;
    if (me.data != null && me.data!.size > 0) {
      _chunks.add(me.data!);
    }
  });

  recorder.addEventListener('stop', (_) async {
    for (final t in _stream?.getTracks() ?? const []) {
      t.stop();
    }
    _stream = null;
    _recorder = null;
    recordingListenable.value = false;
    _maxTimer?.cancel();
    _maxTimer = null;

    final completer = _stopped;
    if (completer == null || completer.isCompleted) return;
    if (_chunks.isEmpty) {
      completer.complete(null);
      return;
    }
    try {
      final blob = html.Blob(_chunks, 'audio/webm');
      final reader = html.FileReader();
      reader.onLoad.listen((_) {
        final result = reader.result;
        if (result is ByteBuffer) {
          completer.complete(result.asUint8List());
        } else if (result is List<int>) {
          completer.complete(Uint8List.fromList(result));
        } else {
          completer.complete(null);
        }
      });
      reader.onError.listen((_) => completer.complete(null));
      reader.readAsArrayBuffer(blob);
    } catch (_) {
      completer.complete(null);
    }
  });

  recordingListenable.value = true;
  recorder.start(200);
  _maxTimer = Timer(maxDuration, () {
    if (recordingListenable.value) {
      stopVoiceRecording();
    }
  });
}

/// Stops recording and returns audio bytes (or null).
Future<Uint8List?> stopVoiceRecording() async {
  final recorder = _recorder;
  final completer = _stopped;
  if (recorder == null) {
    recordingListenable.value = false;
    return null;
  }
  if (recorder.state == 'recording' || recorder.state == 'paused') {
    recorder.stop();
  } else {
    recordingListenable.value = false;
  }
  if (completer == null) return null;
  return completer.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () => null,
  );
}

/// Cancel without returning audio.
Future<void> cancelVoiceRecording() async {
  await stopVoiceRecording();
}

/// One-shot clip (legacy). Prefer start/stop for UI.
Future<Uint8List?> recordVoiceClip({
  Duration maxDuration = const Duration(seconds: 12),
}) async {
  await startVoiceRecording(maxDuration: maxDuration);
  await Future<void>.delayed(maxDuration);
  return stopVoiceRecording();
}
