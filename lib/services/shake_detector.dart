import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import '../data/settings_store.dart';

/// Counts strong shakes; [requiredShakes] within [window] fires [onTriggered].
///
/// Uses user acceleration (gravity removed), so walking, a bumpy rickshaw or
/// putting the phone down stays well below the threshold.
class ShakeDetector {
  ShakeDetector({
    required this.onTriggered,
    this.onShake,
    this.requiredShakes = 3,
    this.window = const Duration(seconds: 2),
  });

  final void Function() onTriggered;

  /// Called on every counted shake with how many are in the current window (for the test screen).
  final void Function(int count)? onShake;
  final int requiredShakes;
  final Duration window;

  /// Peak acceleration in m/s² a movement must exceed to count as a shake.
  static double thresholdFor(ShakeSensitivity s) => switch (s) {
    ShakeSensitivity.low => 26,
    ShakeSensitivity.medium => 19,
    ShakeSensitivity.high => 14,
  };

  // One back-and-forth produces several samples above the line; count it once.
  static const _minGap = Duration(milliseconds: 280);

  double threshold = thresholdFor(ShakeSensitivity.medium);
  StreamSubscription<UserAccelerometerEvent>? _sub;
  final List<DateTime> _peaks = [];
  DateTime _lastPeak = DateTime.fromMillisecondsSinceEpoch(0);

  bool get running => _sub != null;

  void start(ShakeSensitivity sensitivity) {
    threshold = thresholdFor(sensitivity);
    _sub ??= userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
        .listen((e) => addSample(math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z), DateTime.now()), onError: (_) => stop());
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _peaks.clear();
  }

  /// Exposed for tests: feed one acceleration magnitude.
  void addSample(double magnitude, DateTime now) {
    if (magnitude < threshold || now.difference(_lastPeak) < _minGap) return;
    _lastPeak = now;
    _peaks
      ..add(now)
      ..removeWhere((t) => now.difference(t) > window);
    onShake?.call(_peaks.length);
    if (_peaks.length >= requiredShakes) {
      _peaks.clear();
      onTriggered();
    }
  }
}
