import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../data/settings_store.dart';
import '../services/protection_service.dart';
import '../services/scream_detector.dart';
import '../theme.dart';

/// Turning scream detection on: explain what leaves the phone, then ask for the microphone.
Future<void> setScreamEnabled(BuildContext context, bool on) async {
  final settings = context.read<SettingsStore>();
  final protection = context.read<ProtectionService>();
  if (!on) {
    await settings.setScreamEnabled(false);
    return;
  }
  if (!settings.screamConsentGiven) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Listen for screams?'),
        content: const Text(
          'While SafeHer is open, it watches how loud it is around you. Nothing is recorded.\n\n'
          'Only when there is a sudden loud sound, a 2.5-second clip is sent to Google Gemini to '
          'check if it is a scream or a call for help. If it is, the SOS countdown starts and you '
          'have 5 seconds to cancel.\n\n'
          'On the free Gemini plan, Google may use clips to improve its products. Needs internet.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Turn on')),
        ],
      ),
    );
    if (ok != true) return;
    await settings.setScreamConsent();
  }
  final mic = await Permission.microphone.request();
  if (!mic.isGranted) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('SafeHer needs the microphone to listen for screams.')));
    }
    return;
  }
  await settings.setScreamEnabled(true);
  await protection.restartScream();
}

Future<void> openShakeSheet(BuildContext context) => _openTestSheet(context, const _ShakeSheet());

Future<void> openScreamSheet(BuildContext context) => _openTestSheet(context, const _ScreamSheet());

/// While a sheet is open, triggers are shown in it instead of starting a real SOS.
Future<void> _openTestSheet(BuildContext context, Widget sheet) async {
  final protection = context.read<ProtectionService>()
    ..testMode = true
    ..lastTestTrigger = null;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: SafeColors.paper,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => sheet,
  );
  protection.testMode = false;
}

class _TestBanner extends StatelessWidget {
  const _TestBanner();

  @override
  Widget build(BuildContext context) {
    final fired = context.watch<ProtectionService>().lastTestTrigger;
    final color = fired == null ? SafeColors.muted : SafeColors.green;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fired == null ? SafeColors.card : const Color(0xFFDDF1E6),
        border: Border.all(color: SafeColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        fired == null
            ? 'Test mode: nothing is sent while this sheet is open.'
            : 'It worked: SOS would have started from $fired. Nothing was sent.',
        style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ShakeSheet extends StatelessWidget {
  const _ShakeSheet();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final protection = context.watch<ProtectionService>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Shake to alert', style: SafeText.heading(24)),
          const SizedBox(height: 6),
          const Text(
            'Shake the phone hard 3 times within 2 seconds. Works while SafeHer is open.',
            style: SafeText.small,
          ),
          const SizedBox(height: 16),
          const Text('Sensitivity', style: SafeText.bodyStrong),
          const SizedBox(height: 8),
          SegmentedButton<ShakeSensitivity>(
            segments: const [
              ButtonSegment(value: ShakeSensitivity.low, label: Text('Low')),
              ButtonSegment(value: ShakeSensitivity.medium, label: Text('Medium')),
              ButtonSegment(value: ShakeSensitivity.high, label: Text('High')),
            ],
            selected: {settings.shakeSensitivity},
            onSelectionChanged: (s) => settings.setShakeSensitivity(s.first),
          ),
          const SizedBox(height: 6),
          const Text('Low needs harder shakes and gives fewer false alarms.', style: SafeText.caption),
          const SizedBox(height: 18),
          if (!settings.shakeEnabled)
            const Text('Turn on "Shake to alert" to try it.', style: SafeText.bodyStrong)
          else ...[
            Text('Try it now: ${protection.shakeCount} of 3 shakes', style: SafeText.bodyStrong),
            const SizedBox(height: 10),
            const _TestBanner(),
          ],
        ],
      ),
    );
  }
}

class _ScreamSheet extends StatelessWidget {
  const _ScreamSheet();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final scream = context.read<ProtectionService>().scream;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Listen for screams', style: SafeText.heading(24)),
          const SizedBox(height: 6),
          const Text(
            'The phone only measures loudness. A sudden loud sound is sent to Gemini as a short clip, '
            'which decides if it is a scream or a call for help.',
            style: SafeText.small,
          ),
          const SizedBox(height: 18),
          if (!settings.screamEnabled)
            const Text('Turn on "Listen for screams" to try it.', style: SafeText.bodyStrong)
          else
            ValueListenableBuilder<ScreamState>(
              valueListenable: scream.state,
              builder: (context, s, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(screamStatusText(s.status), style: SafeText.bodyStrong),
                  const SizedBox(height: 10),
                  _LevelMeter(level: s.level, ambient: s.ambient),
                  const SizedBox(height: 14),
                  if (s.lastVerdict != null) _VerdictCard(state: s),
                  const SizedBox(height: 10),
                  const Text('Try it: shout "Help! Bachao!" loudly near the phone.', style: SafeText.small),
                  const SizedBox(height: 10),
                  const _TestBanner(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String screamStatusText(ScreamStatus s) => switch (s) {
  ScreamStatus.off => 'Off',
  ScreamStatus.listening => 'Listening for a sudden loud sound…',
  ScreamStatus.checking => 'Loud sound — asking Gemini…',
  ScreamStatus.coolingDown => 'Checked. Listening again in a moment.',
  ScreamStatus.needsInternet => "Couldn't reach Gemini. Only very long, loud sounds will trigger.",
  ScreamStatus.micError => 'Microphone unavailable. Check the permission.',
};

/// Live loudness bar with a mark where "loud" starts, so the decision is visible.
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level, required this.ambient});

  final double level;
  final double ambient;

  // Mirrors LoudnessGate defaults.
  double get _threshold => (ambient + 18) > -24 ? ambient + 18 : -24;

  double _pos(double db) => ((db + 70) / 70).clamp(0, 1);

  @override
  Widget build(BuildContext context) {
    final loud = level > _threshold;
    return LayoutBuilder(
      builder: (context, c) => Stack(
        children: [
          Container(
            height: 14,
            decoration: BoxDecoration(color: SafeColors.line, borderRadius: BorderRadius.circular(7)),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            height: 14,
            width: c.maxWidth * _pos(level),
            decoration: BoxDecoration(
              color: loud ? SafeColors.red : SafeColors.plum,
              borderRadius: BorderRadius.circular(7),
            ),
          ),
          Positioned(
            left: c.maxWidth * _pos(_threshold) - 1,
            child: Container(width: 2, height: 14, color: SafeColors.ink),
          ),
        ],
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.state});

  final ScreamState state;

  @override
  Widget build(BuildContext context) {
    final v = state.lastVerdict!;
    final time = TimeOfDay.fromDateTime(state.lastCheckedAt!).format(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SafeColors.card,
        border: Border.all(color: SafeColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Last check · $time', style: SafeText.caption),
          const SizedBox(height: 2),
          Text('Gemini heard: “${v.heard}”', style: SafeText.body),
          Text(
            '${v.distress ? 'Distress' : 'Not distress'} · ${v.kind.replaceAll('_', ' ')} · '
            '${(v.confidence * 100).round()}% sure',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: v.distress ? SafeColors.red : SafeColors.green,
            ),
          ),
        ],
      ),
    );
  }
}
