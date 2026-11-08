import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// Opens the dialer with the number filled in. SafeHer never places the call itself.
Future<void> callNumber(String number) => launchUrl(Uri(scheme: 'tel', path: number));

class Helpline {
  const Helpline(this.number, this.bangla, this.name, this.detail, this.color);

  final String number;
  final String bangla;
  final String name;
  final String detail;
  final Color color;
}

// Checked 27 Oct 2026 against news sources; verify with official sources before release.
const helplines = [
  Helpline('999', '৯৯৯', 'Police, fire, ambulance', 'National Emergency Service · 24h', SafeColors.red),
  Helpline(
    '109',
    '১০৯',
    'Violence against women & children',
    'Free · 24h · rescue, legal, counselling',
    SafeColors.plum,
  ),
  Helpline('333', '৩৩৩', 'Government info & complaints', 'Child marriage, harassment reports', SafeColors.teal),
  Helpline('1098', '১০৯৮', 'Child helpline', 'For and about children', Color(0xFF5B4E66)),
];

class HelplinesScreen extends StatelessWidget {
  const HelplinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Who to call', style: SafeText.heading(30)),
          const SizedBox(height: 4),
          const Text(
            "Tapping opens your phone's dialer. SafeHer is not linked to these services.",
            style: SafeText.small,
          ),
          const SizedBox(height: 10),
          for (final (i, h) in helplines.indexed) _HelplineRow(h, divider: i < helplines.length - 1),
          const SizedBox(height: 20),
          const Text('Numbers checked 27 Oct 2026 · sources: The Daily Star, Prothom Alo', style: SafeText.caption),
        ],
      ),
    );
  }
}

class _HelplineRow extends StatelessWidget {
  const _HelplineRow(this.h, {required this.divider});

  final Helpline h;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: divider ? const Border(bottom: BorderSide(color: SafeColors.line)) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.number, style: SafeText.heading(34, color: h.color).copyWith(height: 1)),
                const SizedBox(height: 4),
                Text(h.bangla, style: SafeText.caption),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.name, style: SafeText.bodyStrong),
                Text(h.detail, style: SafeText.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Call ${h.number}',
            style: IconButton.styleFrom(
              backgroundColor: h.color,
              minimumSize: const Size(48, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () => callNumber(h.number),
            icon: const Icon(Icons.phone, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }
}
