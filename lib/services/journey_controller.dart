import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../data/settings_store.dart';
import '../data/trusted_contact.dart';
import 'location_service.dart';
import 'permissions.dart';
import 'sms_sender.dart';

/// GPS for a journey. The real one keeps running with the screen off (Android foreground service).
abstract class JourneyTracker {
  Stream<AlertLocation> start();
  Future<void> stop();
}

/// Heads-up when a check-in is due and the app may be in the background.
abstract class JourneyNotifier {
  Future<void> checkInDue(String body);
  Future<void> clear();
}

enum JourneyStage {
  idle,

  /// On the way; next check-in is in the future.
  active,

  /// A check-in is due (timer ran out, or she stopped moving); grace period running.
  checkInDue,

  /// She didn't answer in time; the circle has been told.
  escalated,
}

/// Why a check-in is being asked for.
enum CheckInReason { timer, stopped, overdue }

class JourneyMessage {
  JourneyMessage(this.contact, this.outcome);

  final TrustedContact contact;
  SmsOutcome outcome;
}

/// Runs one Safe Journey: tell the circle, check in on a timer, notice long stops,
/// and alert the circle if she doesn't answer.
class JourneyController extends ChangeNotifier {
  JourneyController({
    required this.tracker,
    required this.notifier,
    this.settings,
    SmsSender? sms,
    Future<bool> Function()? smsAllowed,
    DateTime Function()? clock,
  }) : _sms = sms ?? SmsSender(),
       _smsAllowed = smsAllowed ?? hasSmsPermission,
       _now = clock ?? DateTime.now;

  final JourneyTracker tracker;
  final JourneyNotifier notifier;
  final SettingsStore? settings;
  final SmsSender _sms;
  final Future<bool> Function() _smsAllowed;
  final DateTime Function() _now;

  /// Time to answer a check-in before the circle is told.
  static const grace = Duration(minutes: 2);

  /// Not moving more than [stillRadiusMeters] for this long counts as "stopped".
  static const stoppedFor = Duration(minutes: 6);
  static const stillRadiusMeters = 40.0;

  JourneyStage stage = JourneyStage.idle;
  String destination = '';
  DateTime? arriveBy;
  Duration checkInEvery = const Duration(minutes: 15);
  DateTime? startedAt;
  DateTime? nextCheckIn;
  DateTime? dueSince;
  CheckInReason? dueReason;
  List<TrustedContact> watchers = [];
  final List<JourneyMessage> messages = [];
  final List<LatLng> path = [];
  AlertLocation? lastLocation;

  // Where she last moved more than the still radius; used to detect long stops.
  AlertLocation? _anchor;
  StreamSubscription<AlertLocation>? _gps;
  Timer? _timer;

  bool get onJourney => stage != JourneyStage.idle;

  bool get _shareLocation => settings?.locationSharing != LocationSharing.off;

  String get _name {
    final n = settings?.userName ?? '';
    return n.isEmpty ? 'SafeHer user' : n;
  }

  Duration? get untilCheckIn => nextCheckIn?.difference(_now());

  /// Time left before the circle is told, while a check-in is due.
  Duration? get graceLeft => dueSince?.add(grace).difference(_now());

  Future<void> start({
    required String destination,
    required DateTime arriveBy,
    required Duration checkInEvery,
    required List<TrustedContact> watchers,
  }) async {
    if (onJourney) return;
    this.destination = destination;
    this.arriveBy = arriveBy;
    this.checkInEvery = checkInEvery;
    this.watchers = watchers;
    startedAt = _now();
    nextCheckIn = startedAt!.add(checkInEvery);
    dueSince = null;
    dueReason = null;
    path.clear();
    messages.clear();
    lastLocation = null;
    _anchor = null;
    stage = JourneyStage.active;
    notifyListeners();

    _gps = tracker.start().listen(onLocation);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());

    final by = _hhmm(arriveBy);
    await _sendAll(
      'SafeHer: $_name is on the way to $destination, expecting to arrive by $by. '
      "You'll get a message if a check-in is missed.",
    );
  }

  /// "I'm safe": resets the timer and clears any prompt.
  Future<void> checkIn() async {
    if (!onJourney) return;
    final wasEscalated = stage == JourneyStage.escalated;
    stage = JourneyStage.active;
    dueSince = null;
    dueReason = null;
    nextCheckIn = _now().add(checkInEvery);
    // Moving on from a stop shouldn't immediately count as another stop.
    _anchor = lastLocation;
    await notifier.clear();
    notifyListeners();
    if (wasEscalated) await _sendAll("SafeHer: $_name checked in and is safe now.");
  }

  /// Ends the journey; [arrived] tells the circle she got there.
  Future<void> end({required bool arrived}) async {
    if (!onJourney) return;
    _timer?.cancel();
    await _gps?.cancel();
    _gps = null;
    await tracker.stop();
    await notifier.clear();
    final dest = destination;
    stage = JourneyStage.idle;
    nextCheckIn = null;
    dueSince = null;
    notifyListeners();
    if (arrived) await _sendAll('SafeHer: $_name arrived safely at $dest.');
  }

  /// Called every second; public so tests can drive the clock.
  void tick() {
    if (!onJourney) return;
    final now = _now();
    if (stage == JourneyStage.active) {
      if (nextCheckIn != null && now.isAfter(nextCheckIn!)) {
        _askCheckIn(CheckInReason.timer);
      } else if (arriveBy != null && now.isAfter(arriveBy!.add(grace))) {
        _askCheckIn(CheckInReason.overdue);
      }
    } else if (stage == JourneyStage.checkInDue && graceLeft != null && graceLeft! <= Duration.zero) {
      _escalate();
    }
    notifyListeners();
  }

  /// New GPS fix; public so tests can feed positions.
  void onLocation(AlertLocation loc) {
    if (!onJourney) return;
    lastLocation = loc;
    path.add(LatLng(loc.latitude, loc.longitude));
    final anchor = _anchor;
    if (anchor == null || _distance(anchor, loc) > stillRadiusMeters) {
      _anchor = loc;
    } else if (stage == JourneyStage.active && loc.capturedAt.difference(anchor.capturedAt) >= stoppedFor) {
      _askCheckIn(CheckInReason.stopped);
    }
    notifyListeners();
  }

  void _askCheckIn(CheckInReason reason) {
    stage = JourneyStage.checkInDue;
    dueReason = reason;
    dueSince = _now();
    final why = switch (reason) {
      CheckInReason.timer => "It's time to check in.",
      CheckInReason.stopped => "You've stopped for a while.",
      CheckInReason.overdue => "You're past your arrival time.",
    };
    notifier.checkInDue("$why Tap I'm safe within 2 minutes, or your circle will be told.");
  }

  Future<void> _escalate() async {
    stage = JourneyStage.escalated;
    notifyListeners();
    final why = switch (dueReason) {
      CheckInReason.stopped => 'stopped moving and did not answer a check-in',
      CheckInReason.overdue => 'has not arrived by $_arriveText and did not answer a check-in',
      _ => 'missed a check-in',
    };
    final loc = lastLocation;
    final where = !_shareLocation
        ? ''
        : loc == null
        ? ' Location not available.'
        : ' Last location (${_now().difference(loc.capturedAt).inMinutes} min ago): ${loc.mapsLink}';
    await _sendAll(
      "SafeHer: $_name $why on the way to $destination.$where Please call her.",
      withLocationOnlyFor: (c) => c.getsLocation,
      plain: "SafeHer: $_name $why on the way to $destination. Please call her.",
    );
  }

  String get _arriveText => arriveBy == null ? 'the expected time' : _hhmm(arriveBy!);

  /// Sends [text] to every watcher; contacts that may not see location get [plain] instead.
  Future<void> _sendAll(String text, {bool Function(TrustedContact)? withLocationOnlyFor, String? plain}) async {
    if (watchers.isEmpty) return;
    String body(TrustedContact c) => withLocationOnlyFor == null || withLocationOnlyFor(c) ? text : (plain ?? text);
    if (!await _smsAllowed()) {
      await _sms.openSmsApp(watchers.map((c) => c.phone).toList(), plain ?? text);
      messages.addAll(watchers.map((c) => JourneyMessage(c, SmsOutcome.handedToSmsApp)));
      notifyListeners();
      return;
    }
    final batch = [for (final c in watchers) JourneyMessage(c, SmsOutcome.sending)];
    messages.addAll(batch);
    notifyListeners();
    await Future.wait(
      batch.map((m) async {
        m.outcome = (await _sms.send(m.contact.phone, body(m.contact))).outcome;
        notifyListeners();
      }),
    );
  }

  static double _distance(AlertLocation a, AlertLocation b) =>
      const Distance().as(LengthUnit.Meter, LatLng(a.latitude, a.longitude), LatLng(b.latitude, b.longitude));

  static String _hhmm(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _gps?.cancel();
    super.dispose();
  }
}
