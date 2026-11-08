import '../data/help_guide.dart';
import 'gemini_client.dart';

class ChatTurn {
  const ChatTurn({required this.fromUser, required this.text, this.answer});

  final bool fromUser;
  final String text;

  /// Set on SafeHer's replies.
  final GuideAnswer? answer;
}

class GuideAnswer {
  const GuideAnswer({required this.text, required this.cited, required this.covered, required this.urgent});

  final String text;

  /// Guide entries the answer is based on, in the order Gemini cited them.
  final List<GuideEntry> cited;

  /// False when the guide had nothing on the question and the answer says so.
  final bool covered;

  /// She seems to be in danger right now: the screen shows 999 and SOS first.
  final bool urgent;
}

/// Answers questions only from the checked [HelpGuide], with citations.
///
/// The guide is small (about a dozen entries), so all of it goes in the prompt instead of a
/// separate retrieval step; Gemini may cite only ids that exist (they are an enum in the schema).
class GuideAnswerer {
  GuideAnswerer(this.guide, {GeminiClient? gemini}) : _gemini = gemini ?? GeminiClient();

  final HelpGuide guide;
  final GeminiClient _gemini;

  static const models = [
    GeminiModel('gemini-3.5-flash', {'thinkingBudget': 0}),
    GeminiModel('gemini-flash-lite-latest', {'thinkingLevel': 'minimal'}),
  ];

  Map<String, Object> get _schema => {
    'type': 'OBJECT',
    'properties': {
      'answer': {'type': 'STRING'},
      'cited_ids': {
        'type': 'ARRAY',
        'items': {
          'type': 'STRING',
          'enum': [for (final e in guide.entries) e.id],
        },
      },
      'covered': {'type': 'BOOLEAN'},
      'urgent': {'type': 'BOOLEAN'},
    },
    'propertyOrdering': ['urgent', 'covered', 'cited_ids', 'answer'],
    'required': ['answer', 'cited_ids', 'covered', 'urgent'],
  };

  String prompt(List<ChatTurn> history, String question) {
    final recent = history.length > 6 ? history.sublist(history.length - 6) : history;
    final convo = recent.map((t) => '${t.fromUser ? 'She' : 'SafeHer'}: ${t.text}').join('\n');
    return 'You are Ask SafeHer, the help assistant inside a women\'s safety app in Bangladesh.\n'
        'Answer ONLY from the GUIDE below. Never invent phone numbers, laws, offices, procedures or facts '
        'that are not in it.\n'
        'Reply in the language and script of her latest message: Bangla script for Bangla, romanised '
        'Banglish for Banglish, English for English.\n'
        'Be short and practical: at most 5 numbered steps or 3 sentences, plain text, no markdown.\n'
        'Copy phone numbers exactly as written in the guide. If an entry you use has verify=true, say its '
        'number should be double-checked.\n'
        'If the guide does not cover her question, set covered=false, say you do not have checked '
        'information on that, and suggest calling 109 (or 999 if she is in danger). Do not guess.\n'
        'You are not a lawyer or doctor: do not judge cases or give legal or medical rulings; point to the '
        'helplines in the guide instead.\n'
        'If she says she is in danger right now (being followed, attacked or threatened at this moment), set '
        'urgent=true and start the answer by telling her to call 999 or hold the SOS button.\n'
        'cited_ids: the ids of the guide entries your answer uses.\n\n'
        'GUIDE (checked ${guide.checked}):\n${guide.toPromptText()}\n\n'
        '${convo.isEmpty ? '' : 'CONVERSATION SO FAR:\n$convo\n\n'}'
        'HER QUESTION: $question';
  }

  /// Throws [GeminiException] when no model could answer.
  Future<GuideAnswer> ask(String question, {List<ChatTurn> history = const []}) async {
    final json = await _gemini.generateJson(
      models: models,
      parts: [
        {'text': prompt(history, question)},
      ],
      schema: _schema,
      temperature: 0.1,
    );
    final ids = [for (final id in json['cited_ids'] as List? ?? const []) id as String];
    return GuideAnswer(
      text: (json['answer'] as String? ?? '').trim(),
      cited: [for (final id in ids.toSet()) ?guide.byId(id)],
      covered: json['covered'] as bool? ?? false,
      urgent: json['urgent'] as bool? ?? false,
    );
  }
}
