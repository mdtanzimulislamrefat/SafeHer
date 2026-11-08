import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:safeher/data/incident_report.dart';
import 'package:safeher/data/settings_store.dart';
import 'package:safeher/screens/record_report_screen.dart';
import 'package:safeher/services/protection_service.dart';
import 'package:safeher/services/sos_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safeher/services/gemini_client.dart';
import 'package:safeher/services/report_drafter.dart';

http.Response geminiAnswer(Map<String, Object> json) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': jsonEncode(json)},
            ],
          },
        },
      ],
    }),
  ),
  200,
);

const draft = {
  'transcript': 'Today around nine I was at the Mirpur 10 bus stop…',
  'title': 'Followed from bus stop',
  'summary': 'A man followed me from Mirpur 10 bus stop to Shah Ali market.',
  'when': '8 November 2026, 9:00 PM',
  'where': 'Mirpur 10 bus stop to Shah Ali market',
  'people_involved': 'Man, about 30, blue shirt, black backpack',
  'witnesses': 'Tea stall uncle near the stop',
  'other_details': 'Not mentioned',
  'suggested_help': ['109'],
};

void main() {
  test('falls back to the lighter model when the first is rate-limited', () async {
    final called = <String>[];
    final client = MockClient((req) async {
      called.add(req.url.path.split('/').last);
      return called.length == 1 ? http.Response('{"error":{"code":429}}', 429) : geminiAnswer(draft);
    });
    final drafter = ReportDrafter(
      gemini: GeminiClient(client: client, apiKey: 'k'),
    );
    final f = await drafter.fromVoice(Uint8List(10), language: ReportLanguage.english);

    expect(called, ['gemini-3.5-flash:generateContent', 'gemini-flash-lite-latest:generateContent']);
    expect(f.where, 'Mirpur 10 bus stop to Shah Ali market');
    expect(f.suggestedHelp, ['109']);
  });

  test('reports why it failed when every model is busy', () async {
    final client = MockClient((_) async => http.Response('', 503));
    final drafter = ReportDrafter(
      gemini: GeminiClient(client: client, apiKey: 'k'),
    );
    expect(
      () => drafter.fromText('note', language: ReportLanguage.bangla),
      throwsA(isA<GeminiException>().having((e) => e.failure, 'failure', GeminiFailure.busy)),
    );
  });

  test('the prompt asks for the chosen language and forbids invented details', () {
    final p = ReportDrafter.prompt(language: ReportLanguage.bangla, now: DateTime(2026, 11, 8, 21, 40), typed: false);
    expect(p, contains('in Bangla'));
    expect(p, contains('উল্লেখ নেই'));
    expect(p, contains('Sunday 8 November 2026, 9:40 PM'));
    expect(p, contains('First write transcript'));
  });

  test('a report survives saving and loading, and shares as plain text', () {
    final r = IncidentReport(
      id: '1',
      createdAt: DateTime(2026, 11, 8, 21, 40),
      fields: ReportFields.fromJson(draft),
      language: ReportLanguage.english,
      audioPath: '/data/reports/1.wav',
      aiDrafted: true,
    );
    final back = IncidentReport.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
    expect(back.fields.witnesses, 'Tea stall uncle near the stop');
    expect(back.audioPath, '/data/reports/1.wav');

    final text = back.toShareText();
    expect(text, startsWith('Followed from bus stop'));
    expect(text, contains('Where: Mirpur 10 bus stop to Shah Ali market'));
    expect(text, contains('AI draft from a voice note, checked by me'));
    expect(text, isNot(contains('/data/reports')));
  });

  testWidgets('leaving the report screen without recording does not crash', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStore(prefs);
    final protection = ProtectionService(settings: settings, sos: SosController(prefs), onTrigger: (_, _) {});
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: protection,
        child: const MaterialApp(home: RecordReportScreen(startTyping: true)),
      ),
    );
    expect(find.text('What happened?'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.takeException(), isNull);
    protection.dispose();
  });
}
