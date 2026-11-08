import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safeher/data/help_guide.dart';
import 'package:safeher/services/gemini_client.dart';
import 'package:safeher/services/guide_answerer.dart';

HelpGuide loadGuide() =>
    HelpGuide.fromJson(jsonDecode(File('assets/guide/help_guide.json').readAsStringSync()) as Map<String, dynamic>);

void main() {
  test('every guide entry has a unique id, text and a named source', () {
    final g = loadGuide();
    expect(g.entries, isNotEmpty);
    expect(g.entries.map((e) => e.id).toSet().length, g.entries.length);
    for (final e in g.entries) {
      expect(e.text.trim(), isNotEmpty, reason: e.id);
      expect(e.source.trim(), isNotEmpty, reason: e.id);
    }
  });

  test('the guide includes the core helplines', () {
    final numbers = {for (final e in loadGuide().entries) ...e.numbers};
    expect(numbers, containsAll(['999', '109', '01320000888']));
  });

  test('answers map cited ids to guide entries and carry the danger flag', () async {
    late Map<String, dynamic> sent;
    final client = MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      final answer = jsonEncode({
        'urgent': true,
        'covered': true,
        'cited_ids': ['emergency-999', 'tip-followed', 'emergency-999'],
        'answer': 'Call 999 now or hold SOS.',
      });
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': answer},
                  ],
                },
              },
            ],
          }),
        ),
        200,
      );
    });
    final answerer = GuideAnswerer(
      loadGuide(),
      gemini: GeminiClient(client: client, apiKey: 'k'),
    );
    final a = await answerer.ask('A man is following me right now');

    expect(a.urgent, isTrue);
    expect(a.cited.map((e) => e.id), ['emergency-999', 'tip-followed']);

    // Gemini may only cite ids that exist: they are an enum in the schema.
    final schema = sent['generationConfig']['responseSchema'] as Map<String, dynamic>;
    final allowed = schema['properties']['cited_ids']['items']['enum'] as List;
    expect(allowed, contains('pcsw-cyber'));
    expect(allowed.length, loadGuide().entries.length);
  });

  test('the prompt carries the guide, the history and the no-guessing rule', () {
    final answerer = GuideAnswerer(loadGuide(), gemini: GeminiClient(apiKey: 'k'));
    final p = answerer.prompt(const [ChatTurn(fromUser: true, text: 'earlier question')], 'how do I file a GD?');
    expect(p, contains('[general-diary]'));
    expect(p, contains('She: earlier question'));
    expect(p, contains('Do not guess'));
    expect(p, endsWith('HER QUESTION: how do I file a GD?'));
  });
}
