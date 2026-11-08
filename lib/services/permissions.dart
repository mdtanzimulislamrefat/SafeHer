import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Permission prompts always come after a short explanation, never during an emergency.

Future<bool> hasSmsPermission() => Permission.sms.isGranted;

/// SMS plus "Phone", which lets SafeHer fall back to another SIM when one has no signal.
Future<bool> smsFullySetUp() async => await Permission.sms.isGranted && await Permission.phone.isGranted;

Future<bool> ensureSmsPermission(BuildContext context) async {
  if (await smsFullySetUp()) return true;
  if (!context.mounted) return false;
  final go = await _primer(
    context,
    title: 'Let SafeHer send SMS?',
    body:
        'SOS alerts go out as normal SMS from your SIM, so your circle gets them '
        'even without internet. Standard SMS charges apply.\n\n'
        'Android will also ask about "phone calls": that lets SafeHer see your SIMs and '
        'switch to the one that has signal. SafeHer never makes or reads calls.\n\n'
        'If you say no, SafeHer will open your SMS app with the message ready instead.',
  );
  if (!go) return false;
  final statuses = await [Permission.sms, Permission.phone].request();
  return statuses[Permission.sms]?.isGranted ?? false;
}

Future<bool> hasLocationPermission() async {
  try {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  } on Exception {
    // A broken location plugin must not stop an alert; treat it as "no location".
    return false;
  }
}

Future<bool> ensureLocationPermission(BuildContext context) async {
  if (await hasLocationPermission()) return true;
  if (!context.mounted) return false;
  final go = await _primer(
    context,
    title: 'Add your location to alerts?',
    body:
        'SafeHer reads your location only when you send an alert, and only shares it '
        'with people you allowed. Without it, alerts are sent without a location.',
  );
  if (!go) return false;
  final p = await Geolocator.requestPermission();
  return p == LocationPermission.always || p == LocationPermission.whileInUse;
}

Future<bool> _primer(BuildContext context, {required String title, required String body}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
      ],
    ),
  );
  return ok ?? false;
}
