import 'dart:convert';

import 'package:flutter/services.dart';

/// One checked piece of help information, with where it came from.
class GuideEntry {
  const GuideEntry({
    required this.id,
    required this.title,
    required this.titleBn,
    required this.text,
    required this.numbers,
    required this.source,
    required this.url,
    required this.verify,
  });

  final String id;
  final String title;
  final String titleBn;
  final String text;
  final List<String> numbers;
  final String source;
  final String url;

  /// Not yet confirmed against an official source; shown with a "check this" note.
  final bool verify;

  factory GuideEntry.fromJson(Map<String, dynamic> j) => GuideEntry(
    id: j['id'] as String,
    title: j['title'] as String,
    titleBn: j['title_bn'] as String? ?? '',
    text: j['text'] as String,
    numbers: [for (final n in j['numbers'] as List? ?? const []) n as String],
    source: j['source'] as String,
    url: j['url'] as String? ?? '',
    verify: j['verify'] as bool? ?? false,
  );
}

/// The verified guide Ask SafeHer answers from. Kept as editable JSON in assets/guide.
class HelpGuide {
  const HelpGuide({required this.checked, required this.entries});

  final String checked;
  final List<GuideEntry> entries;

  factory HelpGuide.fromJson(Map<String, dynamic> j) => HelpGuide(
    checked: j['checked'] as String,
    entries: [for (final e in j['entries'] as List) GuideEntry.fromJson(e as Map<String, dynamic>)],
  );

  static Future<HelpGuide> load([AssetBundle? bundle]) async {
    final raw = await (bundle ?? rootBundle).loadString('assets/guide/help_guide.json');
    return HelpGuide.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  GuideEntry? byId(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// The guide as Gemini sees it.
  String toPromptText() {
    return entries
        .map(
          (e) =>
              '[${e.id}] ${e.title}${e.verify ? ' (verify=true: number not yet confirmed officially)' : ''}\n'
              '${e.text}\nSource: ${e.source}',
        )
        .join('\n\n');
  }
}
