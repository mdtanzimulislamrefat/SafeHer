import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import 'journey_controller.dart';
import 'location_service.dart';
import 'permissions.dart';

/// Real GPS. The foreground-service notification keeps the journey alive with the screen off,
/// so check-in timers and escalation still run.
class GeolocatorTracker implements JourneyTracker {
  @override
  Stream<AlertLocation> start() async* {
    if (!await hasLocationPermission()) return;
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      intervalDuration: const Duration(seconds: 15),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'SafeHer · Safe Journey on',
        notificationText: 'Open SafeHer to check in or end your journey.',
        notificationChannelName: 'Safe Journey',
        notificationIcon: AndroidResource(name: 'ic_stat_safeher', defType: 'drawable'),
        color: Color(0xFF4B1D6B),
        setOngoing: true,
        enableWakeLock: true,
      ),
    );
    yield* Geolocator.getPositionStream(locationSettings: settings).map(
      (p) => AlertLocation(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy,
        capturedAt: p.timestamp,
        isLastKnown: false,
      ),
    );
  }

  // Cancelling the stream subscription stops the foreground service.
  @override
  Future<void> stop() async {}
}

class LocalJourneyNotifier implements JourneyNotifier {
  static const _id = 7;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_stat_safeher')),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  /// Ask for the notification permission when a journey starts, not when one is due.
  Future<void> prepare() => _init();

  @override
  Future<void> checkInDue(String body) async {
    await _init();
    await _plugin.show(
      id: _id,
      title: 'Check in with SafeHer',
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'journey_checkin',
          'Journey check-ins',
          channelDescription: 'Asks you to confirm you are safe during a Safe Journey.',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          icon: 'ic_stat_safeher',
          color: Color(0xFF4B1D6B),
        ),
      ),
    );
  }

  @override
  Future<void> clear() async {
    if (_ready) await _plugin.cancel(id: _id);
  }
}
