import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ShakeSensitivity { low, medium, high }

/// Protection switches. Everything is off until the user turns it on.
class SettingsStore extends ChangeNotifier {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  bool get shakeEnabled => _prefs.getBool('shake_enabled') ?? false;
  ShakeSensitivity get shakeSensitivity =>
      ShakeSensitivity.values.asNameMap()[_prefs.getString('shake_sensitivity')] ?? ShakeSensitivity.medium;

  bool get screamEnabled => _prefs.getBool('scream_enabled') ?? false;

  /// The user has read that loud clips go to Google for checking.
  bool get screamConsentGiven => _prefs.getBool('scream_consent') ?? false;

  Future<void> setShakeEnabled(bool v) => _set(() => _prefs.setBool('shake_enabled', v));
  Future<void> setShakeSensitivity(ShakeSensitivity v) => _set(() => _prefs.setString('shake_sensitivity', v.name));
  Future<void> setScreamEnabled(bool v) => _set(() => _prefs.setBool('scream_enabled', v));
  Future<void> setScreamConsent() => _set(() => _prefs.setBool('scream_consent', true));

  Future<void> _set(Future<bool> Function() write) async {
    await write();
    notifyListeners();
  }
}
