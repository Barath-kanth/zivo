import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

/// Fast location for presence / nearby — never hangs, safe on web.
///
/// [Geolocator.getLastKnownPosition] throws on web; skip it there.
Future<Position?> quickPosition({
  Duration timeout = const Duration(seconds: 4),
  String deniedMessage = 'Allow location access to continue.',
}) async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw Exception(deniedMessage);
  }

  Position? last;
  if (!kIsWeb) {
    try {
      last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        final age = DateTime.now().difference(last.timestamp);
        if (age < const Duration(minutes: 10)) return last;
      }
    } catch (_) {
      /* platform may not support last-known */
    }
  }

  try {
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.low,
      timeLimit: timeout,
    );
  } catch (_) {
    if (last != null) return last;
    rethrow;
  }
}
