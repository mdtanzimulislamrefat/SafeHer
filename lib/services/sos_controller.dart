import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/trusted_contact.dart';
import 'location_service.dart';
import 'permissions.dart';
import 'sms_sender.dart';

enum SosTrigger { hold, shake, scream, loudSound }

extension SosTriggerLabel on SosTrigger {
  String get label => switch (this) {
    SosTrigger.hold => 'holding the SOS button',
    SosTrigger.shake => 'shake to alert',
    SosTrigger.scream => 'scream detection',
    SosTrigger.loudSound => 'a very loud sound (AI check offline)',
  };
}

class Delivery {
  Delivery(this.contact, this.outcome);

  final TrustedContact contact;
  SmsOutcome outcome;
  DateTime? sentAt;

  /// Carrier of the SIM that sent it, when known.
  String via = '';

  /// Why the last attempt failed (see [SmsResult.reason]).
  String failReason = '';
}

class SosAlert {
  SosAlert({required this.trigger, required this.startedAt});

  final SosTrigger trigger;
  final DateTime startedAt;
  AlertLocation? location;
  bool locationDone = false;
  bool usedSmsApp = false;
  final List<Delivery> deliveries = [];

  int get leftPhone => deliveries.where((d) => d.outcome == SmsOutcome.sent).length;
}

/// Runs one SOS alert from "countdown finished" to "I'm safe".
class SosController extends ChangeNotifier {
  SosController(this._prefs, {SmsSender? sms, LocationService? location, Future<bool> Function()? smsAllowed})
    : _sms = sms ?? SmsSender(),
      _location = location ?? LocationService(),
      _smsAllowed = smsAllowed ?? hasSmsPermission;

  static const _logKey = 'sos_log_v1';
  final SharedPreferences _prefs;
  final SmsSender _sms;
  final LocationService _location;
  final Future<bool> Function() _smsAllowed;

  SosAlert? _active;
  SosAlert? get active => _active;

  bool _countingDown = false;

  /// True while a countdown or alert is on screen, so other triggers don't stack up.
  bool get busy => _countingDown || _active != null;

  set countingDown(bool v) => _countingDown = v;

  Future<void> dispatch({required SosTrigger trigger, required List<TrustedContact> recipients}) async {
    final alert = SosAlert(trigger: trigger, startedAt: DateTime.now());
    alert.deliveries.addAll(recipients.map((c) => Delivery(c, SmsOutcome.queued)));
    _active = alert;
    notifyListeners();

    // Write the alert down before touching the network, so it survives a crash or no signal.
    await _log({'at': alert.startedAt.toIso8601String(), 'trigger': trigger.name, 'to': recipients.length});

    alert.location = await _location.forAlert();
    alert.locationDone = true;
    notifyListeners();

    if (recipients.isEmpty) return;

    if (await _smsAllowed()) {
      await Future.wait(alert.deliveries.map((d) => _sendOne(alert, d)));
    } else {
      alert.usedSmsApp = true;
      // One shared message: the SMS app can't vary text per recipient.
      final anyLocation = recipients.any((c) => c.getsLocation);
      await _sms.openSmsApp(recipients.map((c) => c.phone).toList(), _sosMessage(alert, includeLocation: anyLocation));
      for (final d in alert.deliveries) {
        d.outcome = SmsOutcome.handedToSmsApp;
      }
      notifyListeners();
    }
  }

  Future<void> retry(Delivery d) async {
    final alert = _active;
    if (alert == null) return;
    await _sendOne(alert, d);
  }

  /// Ends the alert. Optionally tells everyone who got the SOS that she is safe.
  Future<void> endAlert({required bool tellCircle}) async {
    final alert = _active;
    _active = null;
    notifyListeners();
    if (alert == null || !tellCircle || !await _smsAllowed()) return;
    final reached = alert.deliveries.where((d) => d.outcome == SmsOutcome.sent);
    await Future.wait(reached.map((d) => _sms.send(d.contact.phone, "SafeHer: I'm safe now. Thank you.")));
    await _log({'at': DateTime.now().toIso8601String(), 'event': 'safe'});
  }

  Future<void> _sendOne(SosAlert alert, Delivery d) async {
    d.outcome = SmsOutcome.sending;
    notifyListeners();
    final r = await _sms.send(d.contact.phone, _sosMessage(alert, includeLocation: d.contact.getsLocation));
    d.outcome = r.outcome;
    d.via = r.via;
    d.failReason = r.reason;
    if (d.outcome == SmsOutcome.sent) d.sentAt = DateTime.now();
    notifyListeners();
  }

  String _sosMessage(SosAlert alert, {required bool includeLocation}) {
    final b = StringBuffer('SafeHer SOS: I need help now. Please call me.');
    final loc = alert.location;
    if (!includeLocation) {
      // Contact isn't allowed to see location; say nothing about it.
    } else if (loc == null) {
      b.write('\nLocation not available.');
    } else if (loc.isLastKnown) {
      b.write('\nLast known location (${loc.age.inMinutes} min old): ${loc.mapsLink}');
    } else {
      b.write('\nMy location (±${loc.accuracyMeters.round()} m): ${loc.mapsLink}');
    }
    return b.toString();
  }

  Future<void> _log(Map<String, Object> entry) async {
    final log = _prefs.getStringList(_logKey) ?? [];
    log.add(jsonEncode(entry));
    await _prefs.setStringList(_logKey, log);
  }
}
