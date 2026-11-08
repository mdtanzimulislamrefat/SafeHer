import 'dart:typed_data';

import '../data/incident_report.dart';
import 'gemini_client.dart';

/// Turns a voice note (or typed note) into an editable incident report with Gemini.
///
/// Gemini writes the transcript first and fills every other field only from it;
/// in testing this stopped it from inventing place names.
class ReportDrafter {
  ReportDrafter({GeminiClient? gemini}) : _gemini = gemini ?? GeminiClient();

  final GeminiClient _gemini;

  /// Accuracy first; the lighter model takes over when the free tier's per-minute limit is hit.
  static const models = [
    GeminiModel('gemini-3.5-flash', {'thinkingBudget': 0}),
    GeminiModel('gemini-flash-lite-latest', {'thinkingLevel': 'minimal'}),
  ];

  static const Map<String, Object> _schema = {
    'type': 'OBJECT',
    'properties': {
      'transcript': {'type': 'STRING'},
      'title': {'type': 'STRING', 'description': 'Under 8 words.'},
      'summary': {'type': 'STRING', 'description': '2-3 sentences, first person.'},
      'when': {'type': 'STRING'},
      'where': {'type': 'STRING'},
      'people_involved': {'type': 'STRING'},
      'witnesses': {'type': 'STRING'},
      'other_details': {'type': 'STRING'},
      'suggested_help': {
        'type': 'ARRAY',
        'items': {
          'type': 'STRING',
          'enum': ['999', '109', '333', '1098'],
        },
      },
    },
    'propertyOrdering': [
      'transcript',
      'title',
      'summary',
      'when',
      'where',
      'people_involved',
      'witnesses',
      'other_details',
      'suggested_help',
    ],
    'required': [
      'transcript',
      'title',
      'summary',
      'when',
      'where',
      'people_involved',
      'witnesses',
      'other_details',
      'suggested_help',
    ],
  };

  static String prompt({required ReportLanguage language, required DateTime now, required bool typed}) {
    final source = typed ? 'a note she typed' : 'a voice note';
    return 'This is $source from a woman using a personal-safety app in Bangladesh, describing something that '
        'happened to her. She may use Bangla, English or a mix. Turn it into a clear incident report she could '
        'later give to family, the 109 helpline or police. Write every field except transcript in '
        '${language.label}. Use only what she said: if something is not mentioned, write exactly '
        "'${notMentioned(language)}'. Do not add advice, judgement or details she did not say. "
        'Right now it is ${_describe(now)} Bangladesh time; turn relative times like "today at nine" into a date '
        'and time. First write transcript: her words exactly as ${typed ? 'written' : 'spoken'}, in the original '
        'language. Then fill every other field only from that transcript. Copy names of places and people exactly '
        'as she said them. suggested_help lists only helplines that fit what happened.';
  }

  static String notMentioned(ReportLanguage l) => l == ReportLanguage.bangla ? 'উল্লেখ নেই' : 'Not mentioned';

  static String _describe(DateTime t) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '${days[t.weekday - 1]} ${t.day} ${months[t.month - 1]} ${t.year}, $h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// Throws [GeminiException] when no model could answer.
  Future<ReportFields> fromVoice(Uint8List wav, {required ReportLanguage language, DateTime? now}) {
    return _draft([
      inlineData('audio/wav', wav),
      {'text': prompt(language: language, now: now ?? DateTime.now(), typed: false)},
    ]);
  }

  Future<ReportFields> fromText(String note, {required ReportLanguage language, DateTime? now}) {
    return _draft([
      {'text': prompt(language: language, now: now ?? DateTime.now(), typed: true)},
      {'text': 'Her note:\n$note'},
    ]);
  }

  Future<ReportFields> _draft(List<Map<String, Object>> parts) async {
    final json = await _gemini.generateJson(models: models, parts: parts, schema: _schema, temperature: 0.2);
    return ReportFields.fromJson(json);
  }
}
