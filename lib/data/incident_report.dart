/// The written part of a report. Every field is editable by the user.
class ReportFields {
  const ReportFields({
    this.title = '',
    this.summary = '',
    this.when = '',
    this.where = '',
    this.peopleInvolved = '',
    this.witnesses = '',
    this.otherDetails = '',
    this.suggestedHelp = const [],
    this.transcript = '',
  });

  final String title;
  final String summary;
  final String when;
  final String where;
  final String peopleInvolved;
  final String witnesses;
  final String otherDetails;

  /// Helpline numbers, e.g. ["109", "999"].
  final List<String> suggestedHelp;

  /// Her own words, in the language she spoke.
  final String transcript;

  ReportFields copyWith({
    String? title,
    String? summary,
    String? when,
    String? where,
    String? peopleInvolved,
    String? witnesses,
    String? otherDetails,
  }) {
    return ReportFields(
      title: title ?? this.title,
      summary: summary ?? this.summary,
      when: when ?? this.when,
      where: where ?? this.where,
      peopleInvolved: peopleInvolved ?? this.peopleInvolved,
      witnesses: witnesses ?? this.witnesses,
      otherDetails: otherDetails ?? this.otherDetails,
      suggestedHelp: suggestedHelp,
      transcript: transcript,
    );
  }

  Map<String, Object> toJson() => {
    'title': title,
    'summary': summary,
    'when': when,
    'where': where,
    'people_involved': peopleInvolved,
    'witnesses': witnesses,
    'other_details': otherDetails,
    'suggested_help': suggestedHelp,
    'transcript': transcript,
  };

  /// Reads both our stored JSON and Gemini's answer, which use the same keys.
  factory ReportFields.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] as String? ?? '').trim();
    return ReportFields(
      title: s('title'),
      summary: s('summary'),
      when: s('when'),
      where: s('where'),
      peopleInvolved: s('people_involved'),
      witnesses: s('witnesses'),
      otherDetails: s('other_details'),
      suggestedHelp: [for (final h in j['suggested_help'] as List? ?? const []) h as String],
      transcript: s('transcript'),
    );
  }
}

enum ReportLanguage {
  english('English'),
  bangla('Bangla');

  const ReportLanguage(this.label);
  final String label;
}

class IncidentReport {
  const IncidentReport({
    required this.id,
    required this.createdAt,
    required this.fields,
    required this.language,
    this.audioPath,
    this.aiDrafted = false,
  });

  final String id;
  final DateTime createdAt;
  final ReportFields fields;
  final ReportLanguage language;

  /// Voice note in app-private storage; null for typed reports.
  final String? audioPath;

  /// True when Gemini wrote the first draft (shown so nobody mistakes it for her exact words).
  final bool aiDrafted;

  IncidentReport copyWith({ReportFields? fields, ReportLanguage? language}) {
    return IncidentReport(
      id: id,
      createdAt: createdAt,
      fields: fields ?? this.fields,
      language: language ?? this.language,
      audioPath: audioPath,
      aiDrafted: aiDrafted,
    );
  }

  /// Plain text for sharing with family, 109 or police.
  String toShareText() {
    final f = fields;
    final lines = [
      if (f.title.isNotEmpty) f.title,
      '',
      if (f.summary.isNotEmpty) f.summary,
      '',
      'When: ${f.when}',
      'Where: ${f.where}',
      'People involved: ${f.peopleInvolved}',
      'Witnesses: ${f.witnesses}',
      if (f.otherDetails.isNotEmpty) 'Other details: ${f.otherDetails}',
      '',
      'Written with SafeHer${aiDrafted ? ' (AI draft from a voice note, checked by me)' : ''}.',
    ];
    return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'fields': fields.toJson(),
    'language': language.name,
    'audioPath': audioPath,
    'aiDrafted': aiDrafted,
  };

  factory IncidentReport.fromJson(Map<String, dynamic> j) {
    return IncidentReport(
      id: j['id'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      fields: ReportFields.fromJson(j['fields'] as Map<String, dynamic>),
      language: ReportLanguage.values.asNameMap()[j['language']] ?? ReportLanguage.english,
      audioPath: j['audioPath'] as String?,
      aiDrafted: j['aiDrafted'] as bool? ?? false,
    );
  }
}
