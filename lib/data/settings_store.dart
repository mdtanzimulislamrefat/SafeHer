import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ShakeSensitivity { low, medium, high }

/// Who may get her location, per the PDF's "Location-sharing modes".
enum LocationSharing {
  off('Off', 'Alerts are sent without your location.'),
  sosOnly('Emergencies only', 'Location goes out only with an SOS alert.'),
  sosAndJourneys('Emergencies and journeys', 'Also during a Safe Journey, if you miss a check-in.');

  const LocationSharing(this.label, this.detail);
  final String label;
  final String detail;
}

/// Protection switches and preferences. Everything risky is off until the user turns it on.
class SettingsStore extends ChangeNotifier {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  /// Used in alerts ("SafeHer SOS from Rumana") so people who haven't saved her number know who it is.
  String get userName => _prefs.getString('user_name') ?? '';

  LocationSharing get locationSharing =>
      LocationSharing.values.asNameMap()[_prefs.getString('location_sharing')] ?? LocationSharing.sosAndJourneys;

  bool get shakeEnabled => _prefs.getBool('shake_enabled') ?? false;
  ShakeSensitivity get shakeSensitivity =>
      ShakeSensitivity.values.asNameMap()[_prefs.getString('shake_sensitivity')] ?? ShakeSensitivity.medium;

  bool get screamEnabled => _prefs.getBool('scream_enabled') ?? false;

  /// The user has read that loud clips go to Google for checking.
  bool get screamConsentGiven => _prefs.getBool('scream_consent') ?? false;

  /// Ask before a voice note is sent to Gemini for drafting.
  bool get confirmBeforeDrafting => _prefs.getBool('confirm_drafting') ?? true;

  /// Minutes between journey check-ins.
  int get journeyCheckInMinutes => _prefs.getInt('journey_checkin_min') ?? 15;

  Future<void> setUserName(String v) => _set(() => _prefs.setString('user_name', v.trim()));
  Future<void> setLocationSharing(LocationSharing v) => _set(() => _prefs.setString('location_sharing', v.name));
  Future<void> setShakeEnabled(bool v) => _set(() => _prefs.setBool('shake_enabled', v));
  Future<void> setShakeSensitivity(ShakeSensitivity v) => _set(() => _prefs.setString('shake_sensitivity', v.name));
  Future<void> setScreamEnabled(bool v) => _set(() => _prefs.setBool('scream_enabled', v));
  Future<void> setScreamConsent() => _set(() => _prefs.setBool('scream_consent', true));
  Future<void> setConfirmBeforeDrafting(bool v) => _set(() => _prefs.setBool('confirm_drafting', v));
  Future<void> setJourneyCheckInMinutes(int v) => _set(() => _prefs.setInt('journey_checkin_min', v));

  /// Wipes every saved preference on this phone (part of "Delete all my data").
  Future<void> clearAll() => _set(_prefs.clear);

  Future<void> _set(Future<bool> Function() write) async {
    await write();
    notifyListeners();
  }
}
