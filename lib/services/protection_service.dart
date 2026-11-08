import 'package:flutter/widgets.dart';

import '../data/settings_store.dart';
import 'distress_checker.dart';
import 'scream_detector.dart';
import 'shake_detector.dart';
import 'sos_controller.dart';

/// Turns shake and scream listening on and off with the settings and the app's lifecycle.
///
/// Both only run while SafeHer is open on screen; background listening needs an
/// Android foreground service and is a later step.
class ProtectionService extends ChangeNotifier with WidgetsBindingObserver {
  ProtectionService({required this.settings, required this.sos, required this.onTrigger, DistressChecker? checker}) {
    shake = ShakeDetector(onTriggered: () => _fire(SosTrigger.shake, null), onShake: _onShake);
    scream = ScreamDetector(
      checker: checker,
      onDistress: (v) => _fire(v == null ? SosTrigger.loudSound : SosTrigger.scream, v?.heard),
    );
    settings.addListener(_apply);
    WidgetsBinding.instance.addObserver(this);
    _apply();
  }

  final SettingsStore settings;
  final SosController sos;

  /// Opens the SOS countdown; [detail] is shown on it (e.g. what Gemini heard).
  final void Function(SosTrigger trigger, String? detail) onTrigger;

  late final ShakeDetector shake;
  late final ScreamDetector scream;

  bool _foreground = true;

  /// While a test sheet is open, triggers are shown there instead of starting SOS.
  bool testMode = false;
  int shakeCount = 0;
  String? lastTestTrigger;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _apply();
  }

  void _apply() {
    if (_foreground && settings.shakeEnabled) {
      shake.threshold = ShakeDetector.thresholdFor(settings.shakeSensitivity);
      if (!shake.running) shake.start(settings.shakeSensitivity);
    } else {
      shake.stop();
    }
    if (_foreground && settings.screamEnabled) {
      scream.start();
    } else if (scream.running) {
      scream.stop();
    }
    notifyListeners();
  }

  /// Re-checks after a permission change (e.g. the microphone was just allowed).
  Future<void> restartScream() async {
    await scream.stop();
    _apply();
  }

  void _onShake(int count) {
    shakeCount = count;
    notifyListeners();
  }

  void _fire(SosTrigger trigger, String? detail) {
    shakeCount = 0;
    if (testMode) {
      lastTestTrigger = trigger.label;
      notifyListeners();
      return;
    }
    if (sos.busy) return; // already counting down or alerting
    onTrigger(trigger, detail);
  }

  @override
  void dispose() {
    settings.removeListener(_apply);
    WidgetsBinding.instance.removeObserver(this);
    shake.stop();
    scream.stop();
    super.dispose();
  }
}
