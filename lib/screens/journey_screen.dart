import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/contacts_store.dart';
import '../data/settings_store.dart';
import '../data/trusted_contact.dart';
import '../services/journey_controller.dart';
import '../services/journey_platform.dart';
import '../services/permissions.dart';
import '../services/sms_sender.dart';
import '../services/sos_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'circle_screen.dart';
import 'home_screen.dart';

/// Safe Journey tab: set up a trip, or follow the one in progress.
class JourneyScreen extends StatelessWidget {
  const JourneyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final journey = context.watch<JourneyController>();
    return journey.onJourney ? const _ActiveJourney() : const _JourneySetup();
  }
}

class _JourneySetup extends StatefulWidget {
  const _JourneySetup();

  @override
  State<_JourneySetup> createState() => _JourneySetupState();
}

class _JourneySetupState extends State<_JourneySetup> {
  final _destination = TextEditingController();
  TimeOfDay _arriveBy = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 30)));
  int? _every;
  Set<String>? _chosen;
  bool _starting = false;

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  DateTime _arriveDateTime() {
    final now = DateTime.now();
    var t = DateTime(now.year, now.month, now.day, _arriveBy.hour, _arriveBy.minute);
    if (t.isBefore(now)) t = t.add(const Duration(days: 1)); // e.g. 00:30 means tonight
    return t;
  }

  Future<void> _start(List<TrustedContact> candidates) async {
    final dest = _destination.text.trim();
    final watchers = candidates.where((c) => _chosen!.contains(c.id)).toList();
    if (dest.isEmpty) return _snack('Where are you going?');
    if (watchers.isEmpty) return _snack('Choose at least one person to watch your journey.');
    setState(() => _starting = true);
    final journey = context.read<JourneyController>();
    final settings = context.read<SettingsStore>();
    if (settings.locationSharing != LocationSharing.off) await ensureLocationPermission(context);
    if (!mounted) return;
    await ensureSmsPermission(context);
    final notifier = journey.notifier;
    if (notifier is LocalJourneyNotifier) await notifier.prepare();
    await journey.start(
      destination: dest,
      arriveBy: _arriveDateTime(),
      checkInEvery: Duration(minutes: _every ?? settings.journeyCheckInMinutes),
      watchers: watchers,
    );
    if (mounted) setState(() => _starting = false);
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final candidates = context.watch<ContactsStore>().all.where((c) => c.getsJourneys).toList();
    _chosen ??= {for (final c in candidates) c.id};
    final every = _every ?? settings.journeyCheckInMinutes;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Safe Journey', style: SafeText.heading(30)),
          const SizedBox(height: 6),
          const Text(
            'Tell your circle where you are going. Check in on the way; if you miss a check-in, '
            'they get an SMS.',
            style: SafeText.small,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _destination,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Going to', hintText: 'Home · Dhanmondi 27'),
          ),
          const SizedBox(height: 12),
          SafeRow(
            leading: const LeadIcon(Icons.schedule, color: SafeColors.teal, background: SafeColors.tealSoft),
            title: 'Arrive by ${_arriveBy.format(context)}',
            subtitle: 'Tap to change',
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: _arriveBy);
              if (t != null) setState(() => _arriveBy = t);
            },
          ),
          const SizedBox(height: 14),
          const Text('Check in every', style: SafeText.bodyStrong),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 10, label: Text('10 min')),
              ButtonSegment(value: 15, label: Text('15 min')),
              ButtonSegment(value: 30, label: Text('30 min')),
            ],
            selected: {every},
            onSelectionChanged: (s) => setState(() => _every = s.first),
          ),
          const SizedBox(height: 18),
          const SectionLabel('Who watches this journey'),
          if (candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Expanded(child: Text('Nobody in your circle gets journeys yet.', style: SafeText.small)),
                  TextButton(onPressed: () => openContactForm(context), child: const Text('Add someone')),
                ],
              ),
            )
          else
            for (final c in candidates)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _chosen!.contains(c.id),
                onChanged: (v) => setState(() => v! ? _chosen!.add(c.id) : _chosen!.remove(c.id)),
                secondary: Avatar(name: c.name),
                title: Text(c.name, style: SafeText.bodyStrong),
                subtitle: Text(
                  c.getsLocation ? 'Gets your location if needed' : 'Never gets your location',
                  style: SafeText.caption,
                ),
              ),
          const SizedBox(height: 12),
          NoteBox(
            icon: settings.locationSharing == LocationSharing.off ? Icons.location_off : Icons.lock,
            text: settings.locationSharing == LocationSharing.sosAndJourneys
                ? 'They get an SMS now. Your location goes out only if you miss a check-in, and only to people allowed to see it.'
                : 'They get an SMS now. Location sharing for journeys is off in Settings, so missed check-ins are sent without it.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: SafeColors.teal),
            onPressed: _starting ? null : () => _start(candidates),
            icon: const Icon(Icons.directions_walk),
            label: Text(_starting ? 'Starting…' : 'Start journey'),
          ),
        ],
      ),
    );
  }
}

class _ActiveJourney extends StatelessWidget {
  const _ActiveJourney();

  @override
  Widget build(BuildContext context) {
    final j = context.watch<JourneyController>();
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: _JourneyMap(path: j.path)),
          Container(
            decoration: const BoxDecoration(
              color: SafeColors.paper,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, -4))],
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (j.stage == JourneyStage.checkInDue) _DueCard(j),
                  if (j.stage == JourneyStage.escalated) const _EscalatedCard(),
                  if (j.stage == JourneyStage.checkInDue || j.stage == JourneyStage.escalated)
                    const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Going to', style: SafeText.caption),
                            Text(j.destination, style: SafeText.heading(22)),
                            Text(
                              'Arrive by ${TimeOfDay.fromDateTime(j.arriveBy!).format(context)}',
                              style: SafeText.caption,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Next check-in', style: SafeText.caption),
                          Text(
                            j.stage == JourneyStage.active ? _mmss(j.untilCheckIn) : 'Now',
                            style: SafeText.heading(26, color: SafeColors.teal),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _Watchers(j),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: SafeColors.teal,
                            minimumSize: const Size.fromHeight(56),
                          ),
                          onPressed: j.checkIn,
                          icon: const Icon(Icons.check),
                          label: const Text("I'm safe · আমি নিরাপদ"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 96,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                          onPressed: () => _end(context, j),
                          child: const Text('End'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _mmss(Duration? d) {
    if (d == null || d.isNegative) return '0:00';
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _end(BuildContext context, JourneyController j) async {
    final arrived = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End your journey?'),
        content: Text('Tell ${j.watchers.map((c) => c.name).join(', ')} that you arrived safely?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Just end it')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("I've arrived")),
        ],
      ),
    );
    if (arrived != null) await j.end(arrived: arrived);
  }
}

class _JourneyMap extends StatefulWidget {
  const _JourneyMap({required this.path});

  final List<LatLng> path;

  @override
  State<_JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends State<_JourneyMap> {
  final _map = MapController();
  bool _ready = false;
  int _followed = 0;

  @override
  void didUpdateWidget(covariant _JourneyMap old) {
    super.didUpdateWidget(old);
    if (_ready && widget.path.length != _followed && widget.path.isNotEmpty) {
      _followed = widget.path.length;
      _map.move(widget.path.last, _map.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.path.isEmpty) {
      return Container(
        color: const Color(0xFFEEE9E1),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gps_not_fixed, color: SafeColors.muted, size: 32),
            SizedBox(height: 8),
            Text('Waiting for GPS…', style: SafeText.small),
            Text('Timers and check-ins work without it.', style: SafeText.caption),
          ],
        ),
      );
    }
    return FlutterMap(
      mapController: _map,
      options: MapOptions(initialCenter: widget.path.last, initialZoom: 16, onMapReady: () => _ready = true),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.safeher.safeher',
        ),
        PolylineLayer(
          polylines: [Polyline(points: widget.path, strokeWidth: 5, color: SafeColors.teal)],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: widget.path.last,
              width: 40,
              height: 40,
              child: Container(
                decoration: BoxDecoration(color: const Color(0x2E0F5E63), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: SafeColors.teal,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
      ],
    );
  }
}

class _DueCard extends StatelessWidget {
  const _DueCard(this.j);

  final JourneyController j;

  @override
  Widget build(BuildContext context) {
    final left = j.graceLeft ?? Duration.zero;
    final why = switch (j.dueReason) {
      CheckInReason.stopped => "You've stopped for ${JourneyController.stoppedFor.inMinutes} minutes",
      CheckInReason.overdue => "You're past your arrival time",
      _ => 'Time to check in',
    };
    final names = j.watchers.map((c) => c.name).join(', ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: SafeColors.amberSoft, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$why. Everything okay?', style: SafeText.bodyStrong),
          Text(
            "We'll tell $names in ${_ActiveJourney._mmss(left)} if you don't answer.",
            style: const TextStyle(fontSize: 13, color: Color(0xFF6E3B05)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: SafeColors.ink, minimumSize: const Size(0, 46)),
                  onPressed: j.checkIn,
                  child: const Text("I'm okay"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: SafeColors.red, minimumSize: const Size(0, 46)),
                  onPressed: () => startSos(context, SosTrigger.hold),
                  child: const Text('Get help'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EscalatedCard extends StatelessWidget {
  const _EscalatedCard();

  @override
  Widget build(BuildContext context) {
    return const NoteBox(
      icon: Icons.sms,
      color: SafeColors.redDeep,
      background: SafeColors.redSoft,
      text: "You missed a check-in, so your circle was told. Tap I'm safe to let them know you're okay.",
    );
  }
}

/// Last message state per watcher, so she knows who was told.
class _Watchers extends StatelessWidget {
  const _Watchers(this.j);

  final JourneyController j;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [for (final c in j.watchers) StatusDot(color: _color(_last(c)), label: c.name, note: _label(_last(c)))],
    );
  }

  SmsOutcome? _last(TrustedContact c) {
    for (final m in j.messages.reversed) {
      if (m.contact.id == c.id) return m.outcome;
    }
    return null;
  }

  static Color _color(SmsOutcome? o) => switch (o) {
    SmsOutcome.sent => SafeColors.green,
    SmsOutcome.failed => SafeColors.red,
    null => SafeColors.muted,
    _ => SafeColors.amber,
  };

  static String _label(SmsOutcome? o) => switch (o) {
    SmsOutcome.sent => 'told',
    SmsOutcome.failed => 'SMS failed',
    SmsOutcome.handedToSmsApp => 'in SMS app',
    null => 'watching',
    _ => 'sending',
  };
}
