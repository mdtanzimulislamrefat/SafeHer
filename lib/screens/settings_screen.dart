import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../data/contacts_store.dart';
import '../data/reports_store.dart';
import '../data/settings_store.dart';
import '../services/journey_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/safeher_mark.dart';
import 'circle_screen.dart';
import 'protection_sheets.dart';

/// Settings and privacy. There is no account: everything lives on this phone.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text('Settings', style: SafeText.heading(30)),
          const SizedBox(height: 18),
          const SectionLabel('You'),
          SafeRow(
            leading: const LeadIcon(Icons.person),
            title: s.userName.isEmpty ? 'Add your name' : s.userName,
            subtitle: 'Shown in alerts, so people know who sent them',
            trailing: const Icon(Icons.edit, color: SafeColors.faint, size: 20),
            onTap: () => _editName(context, s),
          ),
          SafeRow(
            leading: const LeadIcon(Icons.people),
            title: 'Trusted contacts',
            subtitle: '${context.watch<ContactsStore>().all.length} in your circle',
            trailing: const Icon(Icons.chevron_right, color: SafeColors.faint),
            divider: false,
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const CircleScreen())),
          ),
          const SizedBox(height: 18),
          const SectionLabel('Location sharing'),
          RadioGroup<LocationSharing>(
            groupValue: s.locationSharing,
            onChanged: (v) => s.setLocationSharing(v!),
            child: Column(
              children: [
                for (final m in LocationSharing.values)
                  RadioListTile<LocationSharing>(
                    contentPadding: EdgeInsets.zero,
                    value: m,
                    title: Text(m.label, style: SafeText.bodyStrong),
                    subtitle: Text(m.detail, style: SafeText.caption),
                  ),
              ],
            ),
          ),
          if (s.locationSharing == LocationSharing.off)
            const NoteBox(
              icon: Icons.warning_amber,
              color: SafeColors.amber,
              background: SafeColors.amberSoft,
              text: 'With sharing off, your circle will not know where you are when you send an SOS.',
            ),
          const SizedBox(height: 18),
          const SectionLabel('Protection'),
          SafeRow(
            leading: const LeadIcon(Icons.vibration),
            title: 'Shake to alert',
            subtitle: 'Sensitivity: ${s.shakeSensitivity.name}',
            trailing: Switch(value: s.shakeEnabled, onChanged: s.setShakeEnabled),
            onTap: () => openShakeSheet(context),
          ),
          SafeRow(
            leading: const LeadIcon(Icons.mic),
            title: 'Listen for screams',
            subtitle: 'Loud sounds are checked by Gemini',
            trailing: Switch(value: s.screamEnabled, onChanged: (v) => setScreamEnabled(context, v)),
            onTap: () => openScreamSheet(context),
            divider: false,
          ),
          const SizedBox(height: 18),
          const SectionLabel('Journeys and reports'),
          const SizedBox(height: 6),
          const Text('Default check-in', style: SafeText.bodyStrong),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 10, label: Text('10 min')),
              ButtonSegment(value: 15, label: Text('15 min')),
              ButtonSegment(value: 30, label: Text('30 min')),
            ],
            selected: {s.journeyCheckInMinutes},
            onSelectionChanged: (v) => s.setJourneyCheckInMinutes(v.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.confirmBeforeDrafting,
            onChanged: s.setConfirmBeforeDrafting,
            title: const Text('Ask before sending a note to Gemini', style: SafeText.bodyStrong),
            subtitle: const Text('For incident reports', style: SafeText.caption),
          ),
          const SizedBox(height: 10),
          const SectionLabel('App'),
          const SafeRow(
            leading: LeadIcon(Icons.translate),
            title: 'Language',
            subtitle: 'English, with Bangla on safety actions. Ask SafeHer and reports work in Bangla.',
          ),
          SafeRow(
            leading: const LeadIcon(Icons.notifications),
            title: 'Permissions and notifications',
            subtitle: 'SMS, location, microphone, notifications',
            trailing: const Icon(Icons.open_in_new, color: SafeColors.faint, size: 20),
            onTap: openAppSettings,
          ),
          const SafeRow(
            leading: LeadIcon(Icons.no_accounts),
            title: 'No account needed',
            subtitle: 'Nothing to log in to, so no password to change. Your data stays on this phone.',
            divider: false,
          ),
          const SizedBox(height: 18),
          const SectionLabel('Privacy'),
          SafeRow(
            leading: const LeadIcon(Icons.info_outline),
            title: 'What SafeHer stores and sends',
            trailing: const Icon(Icons.chevron_right, color: SafeColors.faint),
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const _AboutScreen())),
          ),
          SafeRow(
            leading: const LeadIcon(Icons.delete_forever, color: SafeColors.red, background: SafeColors.redSoft),
            title: 'Delete all my data',
            subtitle: 'Contacts, reports, voice notes and settings',
            divider: false,
            onTap: () => _deleteAll(context),
          ),
        ],
      ),
    );
  }

  Future<void> _editName(BuildContext context, SettingsStore s) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: s.userName),
    );
    if (name != null) await s.setUserName(name);
  }

  Future<void> _deleteAll(BuildContext context) async {
    final journey = context.read<JourneyController>();
    final contacts = context.read<ContactsStore>();
    final reports = context.read<ReportsStore>();
    final settings = context.read<SettingsStore>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all your data?'),
        content: const Text(
          'This removes your trusted contacts, every report and voice note, your settings and the SOS '
          'history from this phone. It cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep my data')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: SafeColors.red),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await journey.end(arrived: false);
    await reports.clear();
    await contacts.clear();
    await settings.clearAll(); // last: the stores above write to the same storage
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All SafeHer data was deleted.')));
    }
  }
}

/// Owns its text controller, so it is disposed only after the closing animation has finished.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your name'),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'Rumana'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _name.text), child: const Text('Save')),
      ],
    );
  }
}

class _AboutScreen extends StatelessWidget {
  const _AboutScreen();

  static const _points = [
    (
      'Stored only on this phone',
      'Trusted contacts, settings, incident reports and voice notes. There is no SafeHer server or account.',
    ),
    (
      'Sent by SMS from your SIM',
      'SOS and journey alerts, to the people you chose. Location is added only if your setting and that '
          "person's permission allow it.",
    ),
    (
      'Sent to Google Gemini',
      'Only: a 2.5-second clip after a sudden loud sound (if scream listening is on), a note you choose to '
          'turn into a report, and questions you ask. On the free plan Google may use these to improve its '
          'products.',
    ),
    (
      'What SafeHer cannot promise',
      'That an SMS is delivered or read, that help will come, that a recording is accepted by police or '
          'courts, or that background features work on every phone. It is not connected to 999, 109 or the '
          'police.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          const Align(alignment: Alignment.centerLeft, child: SafeHerMark(size: 56)),
          const SizedBox(height: 14),
          Text('Your data', style: SafeText.heading(30)),
          const SizedBox(height: 16),
          for (final (title, body) in _points) ...[
            Text(title, style: SafeText.bodyStrong),
            const SizedBox(height: 4),
            Text(body, style: SafeText.small),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
