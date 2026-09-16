import 'package:geolocator/geolocator.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/data/models/task.dart' show LatLng;
import 'package:hyperlocal/core/services/location_service.dart';

class LocationRepository {
  Position? _lastKnownPosition;

  Position? get lastKnownPosition => _lastKnownPosition;

  LatLng? get lastKnownLatLng => _lastKnownPosition != null
      ? LatLng(_lastKnownPosition!.latitude, _lastKnownPosition!.longitude)
      : null;

  /// Colombo fallback only when real GPS disabled (legacy demo).
  static Position get _colomboFallback => Position(
        latitude: 6.9271,
        longitude: 79.8612,
        timestamp: DateTime.now(),
        accuracy: 0.0,
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );

  Future<Position?> fetchCurrentPosition() async {
    if (!AppConfig.useRealGps) {
      _lastKnownPosition = _colomboFallback;
      return _lastKnownPosition;
    }

    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        throw Exception('Location services are off — enable GPS for nearby jobs.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        throw Exception('Location permission required for pilot dispatch.');
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
      _lastKnownPosition = pos;
      return pos;
    } catch (e) {
      // Pilot mode: do not silently fake Colombo (trust/distance would lie).
      if (AppConfig.pilotMode || !AppConfig.demoAllowed) rethrow;
      _lastKnownPosition = _colomboFallback;
      return _lastKnownPosition;
    }
  }

  Stream<Position> positionStream() => LocationService.getPositionStream();
}
