import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/sms_sender.dart';
import '../services/sos_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'helplines_screen.dart';

/// Honest per-person view of where each alert is. Never says "delivered".
class SosStatusScreen extends StatelessWidget {
  const SosStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final alert = context.watch<SosController>().active;
    if (alert == null) return const Scaffold(body: SizedBox.shrink());
    final total = alert.deliveries.length;
    final time = TimeOfDay.fromDateTime(alert.startedAt).format(context);

    return PopScope(
      // Leaving by back must not silently end an alert; use "I'm safe now".
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Text(time, style: SafeText.caption),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  const Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: SafeColors.red),
                      SizedBox(width: 8),
                      Text(
                        'ALERT ACTIVE',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: SafeColors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_headline(alert, total), style: SafeText.heading(30)),
                  const SizedBox(height: 8),
                  Text(
                    alert.usedSmsApp
                        ? 'Your SMS app opened with the message ready. Make sure you pressed send. '
                              "If you're in danger, call 999."
                        : "We can't tell if anyone has read them. If you're in danger, call 999.",
                    style: SafeText.small,
                  ),
                  const SizedBox(height: 14),
                  for (final (i, d) in alert.deliveries.indexed) _DeliveryRow(delivery: d, divider: i < total - 1),
                  const SizedBox(height: 10),
                  _LocationCard(alert: alert),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: SafeColors.red,
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: () => callNumber('999'),
                    icon: const Icon(Icons.phone, size: 20),
                    label: const Text('Call 999'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: () => _endAlert(context), child: const Text("I'm safe now")),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _headline(SosAlert alert, int total) {
    if (!alert.locationDone) return 'Getting ready…';
    if (alert.usedSmsApp) return 'Check your\nSMS app';
    final left = alert.leftPhone;
    if (left == total) return total == 1 ? 'Your alert\nleft your phone' : 'All $total alerts\nleft your phone';
    return '$left of $total alerts\nleft your phone';
  }

  Future<void> _endAlert(BuildContext context) async {
    final controller = context.read<SosController>();
    final reached = controller.active?.leftPhone ?? 0;
    final tell = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Glad you are safe'),
        content: Text(
          reached == 0
              ? 'This ends the alert.'
              : 'Send an "I\'m safe now" SMS to the $reached ${reached == 1 ? 'person' : 'people'} who got your alert?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Just end it')),
          if (reached > 0) FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tell them')),
        ],
      ),
    );
    if (tell == null || !context.mounted) return;
    Navigator.pop(context);
    await controller.endAlert(tellCircle: tell);
  }
}

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({required this.delivery, required this.divider});

  final Delivery delivery;
  final bool divider;

  String? _sentNote(BuildContext context) {
    final parts = [
      if (delivery.via.isNotEmpty) 'via ${delivery.via}',
      if (delivery.sentAt != null) TimeOfDay.fromDateTime(delivery.sentAt!).format(context),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _failNote(String reason) => switch (reason) {
    'no_service' => 'no network on any SIM',
    'no_sim' => 'no SIM found',
    'limit' => 'SMS limit reached',
    _ => 'SMS failed',
  };

  @override
  Widget build(BuildContext context) {
    final c = delivery.contact;
    final (color, label, note) = switch (delivery.outcome) {
      SmsOutcome.queued => (SafeColors.muted, 'Queued', null),
      SmsOutcome.sending => (SafeColors.amber, 'Sending', null),
      SmsOutcome.sent => (SafeColors.green, 'Sent', _sentNote(context)),
      SmsOutcome.waiting => (SafeColors.amber, 'Waiting', 'no signal yet'),
      SmsOutcome.failed => (SafeColors.red, 'Not sent', _failNote(delivery.failReason)),
      SmsOutcome.handedToSmsApp => (SafeColors.amber, 'In SMS app', 'press send there'),
    };
    final canRetry = delivery.outcome == SmsOutcome.failed || delivery.outcome == SmsOutcome.waiting;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: divider ? const Border(bottom: BorderSide(color: SafeColors.line)) : null,
      ),
      child: Row(
        children: [
          Avatar(name: c.name),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: c.name,
                    style: SafeText.bodyStrong,
                    children: [if (c.relation.isNotEmpty) TextSpan(text: ' · ${c.relation}', style: SafeText.caption)],
                  ),
                ),
                const SizedBox(height: 2),
                StatusDot(color: color, label: label, note: note),
              ],
            ),
          ),
          if (canRetry)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: SafeColors.plum,
                textStyle: const TextStyle(fontFamily: 'HindSiliguri', fontSize: 13, fontWeight: FontWeight.w600),
              ),
              onPressed: () => context.read<SosController>().retry(delivery),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.alert});

  final SosAlert alert;

  @override
  Widget build(BuildContext context) {
    final loc = alert.location;
    final String title;
    final String detail;
    if (!alert.locationDone) {
      title = 'Finding your location…';
      detail = 'Up to 8 seconds';
    } else if (loc == null) {
      title = 'No location in this alert';
      detail = 'Location is off or unavailable';
    } else if (loc.isLastKnown) {
      title = 'Last known location included';
      detail = '${loc.age.inMinutes} min old · ±${loc.accuracyMeters.round()} m';
    } else {
      title = 'Current location included';
      detail = '±${loc.accuracyMeters.round()} m · only to people allowed to see it';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: SafeColors.card,
        border: Border.all(color: SafeColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(loc == null && alert.locationDone ? Icons.location_off : Icons.place, color: SafeColors.plum, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(detail, style: SafeText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
