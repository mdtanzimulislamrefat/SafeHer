import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/incident_report.dart';
import '../data/reports_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'record_report_screen.dart';
import 'report_edit_screen.dart';

/// Private library of incident reports, newest first.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reports = context.watch<ReportsStore>().all;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Your reports', style: SafeText.heading(30)),
          const SizedBox(height: 6),
          const Text('Write down what happened while you remember it. Only you can see these.', style: SafeText.small),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _open(context, const RecordReportScreen()),
            icon: const Icon(Icons.mic),
            label: const Text('Record what happened'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _open(context, const RecordReportScreen(startTyping: true)),
            icon: const Icon(Icons.keyboard),
            label: const Text('Type it instead'),
          ),
          const SizedBox(height: 20),
          if (reports.isEmpty)
            const Text('No reports yet.', style: SafeText.small)
          else ...[
            const SectionLabel('Saved'),
            for (final (i, r) in reports.indexed) _ReportRow(report: r, divider: i < reports.length - 1),
          ],
        ],
      ),
    );
  }

  static void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.report, required this.divider});

  final IncidentReport report;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final d = report.createdAt;
    final date = '${d.day}/${d.month}/${d.year} · ${TimeOfDay.fromDateTime(d).format(context)}';
    final title = report.fields.title.isEmpty ? 'Untitled report' : report.fields.title;
    return SafeRow(
      leading: LeadIcon(report.audioPath != null ? Icons.mic : Icons.description),
      title: title,
      subtitle: [date, if (report.aiDrafted) 'AI draft'].join(' · '),
      trailing: const Icon(Icons.chevron_right, color: SafeColors.faint),
      divider: divider,
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ReportEditScreen(report: report))),
    );
  }
}
