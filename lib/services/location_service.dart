import 'package:geolocator/geolocator.dart';

import 'permissions.dart';

/// A position plus how fresh it is, so alerts can say "current" or "last known, 12 min ago".
class AlertLocation {
  const AlertLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
    required this.isLastKnown,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime capturedAt;
  final bool isLastKnown;

  String get mapsLink => 'https://maps.google.com/?q=${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';

  Duration get age => DateTime.now().difference(capturedAt);
}

class LocationService {
  /// Never prompts: during an emergency we use what we're already allowed to read.
  Future<AlertLocation?> forAlert({Duration timeout = const Duration(seconds: 8)}) async {
    if (!await hasLocationPermission()) return null;
    if (!await Geolocator.isLocationServiceEnabled()) return _lastKnown();
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeout),
      );
      return AlertLocation(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy,
        capturedAt: p.timestamp,
        isLastKnown: false,
      );
    } catch (_) {
      return _lastKnown();
    }
  }

  Future<AlertLocation?> _lastKnown() async {
    try {
      final p = await Geolocator.getLastKnownPosition();
      if (p == null) return null;
      return AlertLocation(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy,
        capturedAt: p.timestamp,
        isLastKnown: true,
      );
    } catch (_) {
      return null;
    }
  }
}
