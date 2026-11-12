import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:safeher/data/contacts_store.dart';
import 'package:safeher/data/settings_store.dart';
import 'package:safeher/data/trusted_contact.dart';
import 'package:safeher/screens/settings_screen.dart';
import 'package:safeher/screens/sos_countdown_screen.dart';
import 'package:safeher/services/location_service.dart';
import 'package:safeher/services/sms_sender.dart';
import 'package:safeher/services/sos_controller.dart';
import 'package:safeher/theme.dart';
import 'package:safeher/widgets/safeher_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSms extends SmsSender {
  FakeSms(this.results);

  /// Outcomes to return, in order; the last one repeats.
  final List<SmsOutcome> results;
  final sent = <(String, String)>[];

  @override
  Future<SmsResult> send(String phone, String message) async {
    sent.add((phone, message));
    return SmsResult(results[(sent.length - 1).clamp(0, results.length - 1)], via: 'Grameenphone');
  }

  @override
  Future<bool> openSmsApp(List<String> phones, String message) async => true;
}

class FakeLocation extends LocationService {
  @override
  Future<AlertLocation?> forAlert({Duration timeout = const Duration(seconds: 8)}) async {
    return AlertLocation(
      latitude: 23.8069,
      longitude: 90.3687,
      accuracyMeters: 12,
      capturedAt: DateTime.now(),
      isLastKnown: false,
    );
  }
}

const ammu = TrustedContact(id: '1', name: 'Ammu', phone: '+8801712345678');
const rafi = TrustedContact(id: '2', name: 'Rafi', phone: '+8801655123551', getsLocation: false);

Future<SosController> controllerWith(FakeSms sms, {bool smsAllowed = true}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return SosController(prefs, sms: sms, location: FakeLocation(), smsAllowed: () async => smsAllowed);
}

void main() {
  group('normalizePhone', () {
    test('accepts Bangladeshi mobiles in local and international form', () {
      expect(normalizePhone('01712 345678'), '+8801712345678');
      expect(normalizePhone('8801712345678'), '+8801712345678');
      expect(normalizePhone('+8801712-345678'), '+8801712345678');
    });

    test('rejects landlines, short numbers and text', () {
      expect(normalizePhone('0212345678'), isNull);
      expect(normalizePhone('01212345678'), isNull);
      expect(normalizePhone('call me'), isNull);
    });
  });

  group('SosController', () {
    test('location goes only to contacts allowed to see it', () async {
      final sms = FakeSms([SmsOutcome.sent]);
      final c = await controllerWith(sms);
      await c.dispatch(trigger: SosTrigger.hold, recipients: [ammu, rafi]);

      final toAmmu = sms.sent.firstWhere((m) => m.$1 == ammu.phone).$2;
      final toRafi = sms.sent.firstWhere((m) => m.$1 == rafi.phone).$2;
      expect(toAmmu, contains('maps.google.com'));
      expect(toRafi, isNot(contains('maps.google.com')));
      expect(c.active!.leftPhone, 2);
    });

    test('a failed SMS stays "failed" until a retry succeeds', () async {
      final sms = FakeSms([SmsOutcome.failed, SmsOutcome.sent]);
      final c = await controllerWith(sms);
      await c.dispatch(trigger: SosTrigger.hold, recipients: [ammu]);

      final d = c.active!.deliveries.single;
      expect(d.outcome, SmsOutcome.failed);
      await c.retry(d);
      expect(d.outcome, SmsOutcome.sent);
    });

    test('without SMS permission it hands off to the SMS app and claims nothing', () async {
      final sms = FakeSms([SmsOutcome.sent]);
      final c = await controllerWith(sms, smsAllowed: false);
      await c.dispatch(trigger: SosTrigger.hold, recipients: [ammu, rafi]);

      expect(sms.sent, isEmpty);
      expect(c.active!.usedSmsApp, isTrue);
      expect(c.active!.deliveries.every((d) => d.outcome == SmsOutcome.handedToSmsApp), isTrue);
    });
  });

  test('SOS uses her name, and skips location when sharing is off', () async {
    SharedPreferences.setMockInitialValues({'user_name': 'Rumana', 'location_sharing': 'off'});
    final prefs = await SharedPreferences.getInstance();
    final sms = FakeSms([SmsOutcome.sent]);
    final c = SosController(
      prefs,
      settings: SettingsStore(prefs),
      sms: sms,
      location: FakeLocation(),
      smsAllowed: () async => true,
    );
    await c.dispatch(trigger: SosTrigger.hold, recipients: [ammu]);
    expect(sms.sent.single.$2, startsWith('SafeHer SOS from Rumana'));
    expect(sms.sent.single.$2, isNot(contains('maps.google.com')));
    expect(c.active!.location, isNull);
  });

  testWidgets('cancelling the countdown sends nothing', (tester) async {
    final sms = FakeSms([SmsOutcome.sent]);
    final c = await controllerWith(sms);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const SosCountdownScreen(trigger: SosTrigger.hold, recipients: [ammu]),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Not pumpAndSettle: the ring animates for the whole countdown, so settling would let it fire.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('5'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text("I'm okay — cancel"));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));

    expect(c.active, isNull);
    expect(sms.sent, isEmpty);
  });

  testWidgets('saving a name in Settings does not crash and updates the name', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStore(prefs);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: ContactsStore(prefs)),
        ],
        child: MaterialApp(theme: buildTheme(), home: const SettingsScreen()),
      ),
    );
    await tester.tap(find.text('Add your name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Rumana');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(settings.userName, 'Rumana');
    expect(find.text('Rumana'), findsOneWidget);
  });

  testWidgets('the logo draws and is announced as SafeHer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: SafeHerLogo())),
      ),
    );
    expect(find.bySemanticsLabel('SafeHer'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
