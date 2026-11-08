import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/incident_report.dart';
import '../data/reports_store.dart';
import '../services/gemini_client.dart';
import '../services/report_drafter.dart';
import '../theme.dart';
import '../widgets/voice_note_player.dart';
import 'helplines_screen.dart';

/// Check and correct the draft, then save it to the private library or share it.
class ReportEditScreen extends StatefulWidget {
  const ReportEditScreen({super.key, required this.report, this.isNew = false});

  final IncidentReport report;
  final bool isNew;

  @override
  State<ReportEditScreen> createState() => _ReportEditScreenState();
}

class _ReportEditScreenState extends State<ReportEditScreen> {
  late IncidentReport _report = widget.report;
  late bool _saved = !widget.isNew;
  bool _redrafting = false;

  late final _title = TextEditingController();
  late final _summary = TextEditingController();
  late final _when = TextEditingController();
  late final _where = TextEditingController();
  late final _people = TextEditingController();
  late final _witnesses = TextEditingController();
  late final _other = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fill(_report.fields);
  }

  @override
  void dispose() {
    for (final c in [_title, _summary, _when, _where, _people, _witnesses, _other]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(ReportFields f) {
    _title.text = f.title;
    _summary.text = f.summary;
    _when.text = f.when;
    _where.text = f.where;
    _people.text = f.peopleInvolved;
    _witnesses.text = f.witnesses;
    _other.text = f.otherDetails;
  }

  IncidentReport _current() => _report.copyWith(
    fields: _report.fields.copyWith(
      title: _title.text.trim(),
      summary: _summary.text.trim(),
      when: _when.text.trim(),
      where: _where.text.trim(),
      peopleInvolved: _people.text.trim(),
      witnesses: _witnesses.text.trim(),
      otherDetails: _other.text.trim(),
    ),
  );

  Future<void> _save() async {
    await context.read<ReportsStore>().save(_current());
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved on this phone only.')));
    Navigator.pop(context);
  }

  Future<void> _share() async {
    await SharePlus.instance.share(ShareParams(text: _current().toShareText()));
  }

  /// Rewrites the draft in the other language from the voice note (or her transcript). Overwrites edits.
  Future<void> _switchLanguage(ReportLanguage lang) async {
    if (lang == _report.language) return;
    final drafter = ReportDrafter();
    setState(() => _redrafting = true);
    try {
      final path = _report.audioPath;
      final fields = path != null
          ? await drafter.fromVoice(await File(path).readAsBytes(), language: lang, now: _report.createdAt)
          : await drafter.fromText(_report.fields.transcript, language: lang, now: _report.createdAt);
      if (!mounted) return;
      setState(() => _report = _report.copyWith(fields: fields, language: lang));
      _fill(fields);
    } on GeminiException {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Couldn't rewrite it now. Try again in a minute.")));
      }
    } finally {
      if (mounted) setState(() => _redrafting = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this report?'),
        content: const Text('The report and its voice note will be removed from this phone. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: SafeColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<ReportsStore>().delete(_report);
    if (mounted) Navigator.pop(context);
  }

  /// Leaving a new, unsaved report: confirm, and don't leave its voice note behind.
  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text('This report and its voice note will not be kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    if (ok == true && _report.audioPath != null) File(_report.audioPath!).delete().ignore();
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return PopScope(
      canPop: _saved,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) {
          setState(() => _saved = true);
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(tooltip: 'Share', onPressed: _share, icon: const Icon(Icons.ios_share)),
            if (!widget.isNew)
              IconButton(
                tooltip: 'Delete',
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline, color: SafeColors.red),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('What happened', style: SafeText.heading(30)),
            const SizedBox(height: 4),
            Text(
              r.aiDrafted
                  ? 'Drafted by Gemini from your ${r.audioPath != null ? 'voice note' : 'note'}. Check it before you share.'
                  : 'Write it the way you remember it.',
              style: SafeText.small,
            ),
            const SizedBox(height: 14),
            if (r.audioPath != null) ...[VoiceNotePlayer(path: r.audioPath!), const SizedBox(height: 10)],
            if (r.aiDrafted || r.fields.transcript.isNotEmpty)
              Row(
                children: [
                  for (final lang in ReportLanguage.values) ...[
                    ChoiceChip(
                      label: Text(lang == ReportLanguage.bangla ? 'বাংলা' : 'English'),
                      selected: r.language == lang,
                      onSelected: _redrafting ? null : (_) => _switchLanguage(lang),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (_redrafting)
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            const SizedBox(height: 6),
            _Field(label: 'Title', controller: _title),
            _Field(label: 'Summary', controller: _summary, multiline: true),
            _Field(label: 'When', controller: _when),
            _Field(label: 'Where', controller: _where),
            _Field(label: 'Person', controller: _people, multiline: true),
            _Field(label: 'Witness', controller: _witnesses),
            _Field(label: 'Other', controller: _other, multiline: true, divider: false),
            if (r.fields.suggestedHelp.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Who can help', style: SafeText.bodyStrong),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final n in r.fields.suggestedHelp)
                    ActionChip(
                      avatar: const Icon(Icons.phone, size: 16, color: SafeColors.plum),
                      label: Text(n),
                      onPressed: () => callNumber(n),
                    ),
                ],
              ),
            ],
            if (r.fields.transcript.isNotEmpty) ...[
              const SizedBox(height: 8),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Your own words', style: SafeText.bodyStrong),
                  subtitle: const Text('What Gemini heard, word for word', style: SafeText.caption),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(r.fields.transcript, style: SafeText.body),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.lock, size: 14, color: SafeColors.muted),
                SizedBox(width: 6),
                Expanded(child: Text('Saved only on this phone. Sharing is up to you.', style: SafeText.caption)),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton(onPressed: _save, child: const Text('Save report')),
          ],
        ),
      ),
    );
  }
}

/// Label-left, value-right row like the v2 design, but editable.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.controller, this.multiline = false, this.divider = true});

  final String label;
  final TextEditingController controller;
  final bool multiline;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: divider ? const Border(bottom: BorderSide(color: SafeColors.line)) : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(label, style: SafeText.caption),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: multiline ? 6 : 2,
              style: SafeText.body,
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
