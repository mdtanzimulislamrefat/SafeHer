import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/contacts_store.dart';
import '../services/permissions.dart';
import '../services/sos_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/hold_to_alert.dart';
import 'circle_screen.dart';
import 'helplines_screen.dart';
import 'sos_countdown_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool? _locationOn;
  bool? _smsReady;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from system settings may have changed the permission.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final location = await hasLocationPermission();
    final sms = await smsFullySetUp();
    if (mounted) {
      setState(() {
        _locationOn = location;
        _smsReady = sms;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ContactsStore>().all;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Text('SafeHer', style: SafeText.heading(20, color: SafeColors.plum)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                const SizedBox(height: 6),
                Text(_greeting(DateTime.now()), style: SafeText.heading(30)),
                const SizedBox(height: 10),
                _CircleSummary(names: contacts.map((c) => c.name).toList()),
                if (_smsReady == false && contacts.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _SetupBanner(
                    icon: Icons.sms_failed_outlined,
                    text: 'Finish SMS setup so alerts can use whichever SIM has signal.',
                    onTap: () async {
                      await ensureSmsPermission(context);
                      await _refreshPermissions();
                    },
                  ),
                ],
                if (_locationOn == false) ...[
                  const SizedBox(height: 14),
                  _SetupBanner(
                    icon: Icons.location_off,
                    text: 'Alerts will go out without your location.',
                    onTap: () async {
                      await ensureLocationPermission(context);
                      await _refreshPermissions();
                    },
                  ),
                ],
                const SizedBox(height: 22),
                const SectionLabel('Protection'),
                const SafeRow(
                  leading: LeadIcon(Icons.mic),
                  title: 'Listen for screams',
                  subtitle: 'On-device only. Nothing is recorded.',
                  trailing: _SoonTag(),
                ),
                const SafeRow(
                  leading: LeadIcon(Icons.vibration),
                  title: 'Shake to alert',
                  subtitle: '3 strong shakes start the countdown',
                  trailing: _SoonTag(),
                  divider: false,
                ),
                const SizedBox(height: 18),
                const SectionLabel('Tools'),
                SafeRow(
                  leading: const LeadIcon(Icons.phone, color: SafeColors.red, background: SafeColors.redSoft),
                  title: 'Helplines',
                  subtitle: '999 · 109 · 333 · 1098',
                  trailing: const Icon(Icons.chevron_right, color: SafeColors.faint),
                  onTap: () =>
                      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const HelplinesScreen())),
                ),
                const SafeRow(
                  leading: LeadIcon(Icons.place, color: SafeColors.teal, background: SafeColors.tealSoft),
                  title: 'Start a safe journey',
                  trailing: _SoonTag(),
                ),
                const SafeRow(
                  leading: LeadIcon(Icons.description),
                  title: 'Write down what happened',
                  subtitle: 'Speak in Bangla or English',
                  trailing: _SoonTag(),
                  divider: false,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
            child: HoldToAlert(onTriggered: () => startSos(context, SosTrigger.hold)),
          ),
        ],
      ),
    );
  }
}

String _greeting(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 12) return 'শুভ সকাল';
  if (h >= 12 && h < 16) return 'শুভ দুপুর';
  if (h >= 16 && h < 18) return 'শুভ বিকেল';
  if (h >= 18 && h < 21) return 'শুভ সন্ধ্যা';
  return 'শুভ রাত্রি';
}

/// Shared entry point for every SOS trigger (hold now; shake and scream later).
Future<void> startSos(BuildContext context, SosTrigger trigger) async {
  final recipients = context.read<ContactsStore>().sosRecipients;
  if (recipients.isEmpty) {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: SafeColors.paper,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nobody to alert yet', style: SafeText.heading(24)),
            const SizedBox(height: 6),
            const Text('Add someone to your circle so SOS can reach them.', style: SafeText.small),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: SafeColors.red),
              onPressed: () => callNumber('999'),
              icon: const Icon(Icons.phone),
              label: const Text('Call 999 now'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(ctx);
                openContactForm(context);
              },
              child: const Text('Add someone'),
            ),
          ],
        ),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => SosCountdownScreen(trigger: trigger, recipients: recipients),
    ),
  );
}

class _CircleSummary extends StatelessWidget {
  const _CircleSummary({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) {
      return InkWell(
        onTap: () => openContactForm(context),
        child: const Row(
          children: [
            Icon(Icons.person_add_alt, size: 20, color: SafeColors.plum),
            SizedBox(width: 8),
            Text(
              'Add someone to your circle',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: SafeColors.plum),
            ),
          ],
        ),
      );
    }
    return Row(
      children: [
        AvatarStack(names: names),
        const SizedBox(width: 10),
        Expanded(child: Text('${_joinNames(names)} can reach you', style: SafeText.small)),
      ],
    );
  }

  static String _joinNames(List<String> n) {
    if (n.length == 1) return n.first;
    if (n.length <= 3) return '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';
    return '${n.take(2).join(', ')} and ${n.length - 2} more';
  }
}

class _SetupBanner extends StatelessWidget {
  const _SetupBanner({required this.icon, required this.text, required this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(color: SafeColors.amberSoft, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, size: 20, color: SafeColors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF6E3B05))),
          ),
          TextButton(onPressed: onTap, child: const Text('Turn on')),
        ],
      ),
    );
  }
}

class _SoonTag extends StatelessWidget {
  const _SoonTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: SafeColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('Soon', style: SafeText.caption),
    );
  }
}
