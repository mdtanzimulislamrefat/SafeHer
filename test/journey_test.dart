import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:safeher/data/settings_store.dart';
import 'package:safeher/data/trusted_contact.dart';
import 'package:safeher/services/journey_controller.dart';
import 'package:safeher/services/location_service.dart';
import 'package:safeher/services/sms_sender.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeSms;

class FakeTracker implements JourneyTracker {
  final controller = StreamController<AlertLocation>();
  bool stopped = false;

  @override
  Stream<AlertLocation> start() => controller.stream;

  @override
  Future<void> stop() async => stopped = true;
}

class FakeNotifier implements JourneyNotifier {
  final shown = <String>[];

  @override
  Future<void> checkInDue(String body) async => shown.add(body);

  @override
  Future<void> clear() async {}
}

const ammu = TrustedContact(id: '1', name: 'Ammu', phone: '+8801712345678');
const rafi = TrustedContact(id: '2', name: 'Rafi', phone: '+8801655123551', getsLocation: false);

AlertLocation at(double lat, double lng, DateTime t) =>
    AlertLocation(latitude: lat, longitude: lng, accuracyMeters: 10, capturedAt: t, isLastKnown: false);

void main() {
  late DateTime now;
  late FakeSms sms;
  late FakeNotifier notifier;
  late FakeTracker tracker;
  late SettingsStore settings;
  late JourneyController j;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'user_name': 'Rumana'});
    settings = SettingsStore(await SharedPreferences.getInstance());
    now = DateTime(2026, 11, 8, 21, 0);
    sms = FakeSms([SmsOutcome.sent]);
    notifier = FakeNotifier();
    tracker = FakeTracker();
    j = JourneyController(
      tracker: tracker,
      notifier: notifier,
      settings: settings,
      sms: sms,
      smsAllowed: () async => true,
      clock: () => now,
    );
    await j.start(
      destination: 'Dhanmondi 27',
      arriveBy: DateTime(2026, 11, 8, 21, 40),
      checkInEvery: const Duration(minutes: 15),
      watchers: [ammu, rafi],
    );
  });

  tearDown(() async {
    await j.end(arrived: false);
    j.dispose();
  });

  test('starting tells every watcher where she is going', () {
    expect(sms.sent.length, 2);
    expect(sms.sent.first.$2, contains('Rumana is on the way to Dhanmondi 27'));
    expect(sms.sent.first.$2, contains('9:40 PM'));
  });

  test('a missed check-in prompts first, then tells the circle after the grace period', () async {
    now = now.add(const Duration(minutes: 15, seconds: 1));
    j.tick();
    expect(j.stage, JourneyStage.checkInDue);
    expect(notifier.shown, hasLength(1));
    expect(sms.sent.length, 2, reason: 'nothing sent during the grace period');

    j.onLocation(at(23.7465, 90.3760, now));
    now = now.add(JourneyController.grace + const Duration(seconds: 1));
    j.tick();
    await pumpEventQueue();

    expect(j.stage, JourneyStage.escalated);
    final toAmmu = sms.sent.last.$1 == ammu.phone ? sms.sent.last.$2 : sms.sent[sms.sent.length - 2].$2;
    final toRafi = sms.sent.last.$1 == rafi.phone ? sms.sent.last.$2 : sms.sent[sms.sent.length - 2].$2;
    expect(toAmmu, contains('missed a check-in'));
    expect(toAmmu, contains('maps.google.com'));
    expect(toRafi, isNot(contains('maps.google.com')), reason: 'Rafi may not see her location');
  });

  test("checking in resets the timer; after an escalation it tells the circle she's safe", () async {
    now = now.add(const Duration(minutes: 10));
    await j.checkIn();
    expect(j.stage, JourneyStage.active);
    expect(j.untilCheckIn, const Duration(minutes: 15));

    now = now.add(const Duration(minutes: 18));
    j.tick();
    now = now.add(const Duration(minutes: 3));
    j.tick();
    await pumpEventQueue();
    expect(j.stage, JourneyStage.escalated);

    await j.checkIn();
    expect(sms.sent.last.$2, contains('checked in and is safe now'));
  });

  test('standing still for 6 minutes asks for a check-in early', () {
    j.onLocation(at(23.7465, 90.3760, now));
    j.onLocation(at(23.74652, 90.37601, now.add(const Duration(minutes: 3))));
    expect(j.stage, JourneyStage.active);
    j.onLocation(at(23.74651, 90.37602, now.add(const Duration(minutes: 6))));
    expect(j.stage, JourneyStage.checkInDue);
    expect(j.dueReason, CheckInReason.stopped);
  });

  test('walking does not count as stopping', () {
    for (var i = 0; i <= 8; i++) {
      // About 110 m north per minute.
      j.onLocation(at(23.7465 + i * 0.001, 90.3760, now.add(Duration(minutes: i))));
    }
    expect(j.stage, JourneyStage.active);
  });

  test('with location sharing off, a missed check-in goes out without a location', () async {
    await settings.setLocationSharing(LocationSharing.off);
    j.onLocation(at(23.7465, 90.3760, now));
    now = now.add(const Duration(minutes: 18));
    j.tick();
    now = now.add(const Duration(minutes: 3));
    j.tick();
    await pumpEventQueue();
    expect(sms.sent.skip(2).any((m) => m.$2.contains('maps.google.com')), isFalse);
  });

  test('arriving tells the circle and stops tracking', () async {
    await j.end(arrived: true);
    expect(sms.sent.last.$2, contains('arrived safely at Dhanmondi 27'));
    expect(tracker.stopped, isTrue);
    expect(j.onJourney, isFalse);
  });
}
