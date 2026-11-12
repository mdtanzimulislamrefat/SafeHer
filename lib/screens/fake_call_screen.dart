import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/contacts_store.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _ringer = MethodChannel('safeher/ringer');

/// Fake Call: a pretend incoming call to get out of an uncomfortable situation.
/// No real call is placed. Labelled as simulated here, never on the call screen itself.
class FakeCallSetupScreen extends StatefulWidget {
  const FakeCallSetupScreen({super.key});

  @override
  State<FakeCallSetupScreen> createState() => _FakeCallSetupScreenState();
}

class _FakeCallSetupScreenState extends State<FakeCallSetupScreen> {
  late final _caller = TextEditingController(text: _defaultCaller());
  int _delay = 10;

  String _defaultCaller() {
    final contacts = context.read<ContactsStore>().all;
    return contacts.isEmpty ? 'Ammu' : contacts.first.name;
  }

  @override
  void dispose() {
    _caller.dispose();
    super.dispose();
  }

  void _start() {
    final name = _caller.text.trim().isEmpty ? 'Ammu' : _caller.text.trim();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _WaitingScreen(
          caller: name,
          delay: Duration(seconds: _delay),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Fake call', style: SafeText.heading(30)),
          const SizedBox(height: 6),
          const Text(
            'Your phone rings with your real ringtone, so you have a reason to step away.',
            style: SafeText.small,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _caller,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Caller name'),
          ),
          const SizedBox(height: 16),
          const Text('Ring after', style: SafeText.bodyStrong),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 3, label: Text('Now')),
              ButtonSegment(value: 10, label: Text('10 s')),
              ButtonSegment(value: 30, label: Text('30 s')),
              ButtonSegment(value: 60, label: Text('1 min')),
            ],
            selected: {_delay},
            onSelectionChanged: (s) => setState(() => _delay = s.first),
          ),
          const SizedBox(height: 18),
          const NoteBox(
            icon: Icons.info_outline,
            text:
                'Simulated: no real call is made and nobody is on the line. Keep SafeHer open until it '
                'rings. People who know phones well may notice. It cannot keep you safe on its own; '
                'use SOS if you are in danger.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.phone_callback),
            label: const Text('Start fake call'),
          ),
        ],
      ),
    );
  }
}

/// Plain dark screen while waiting, so the phone looks idle.
class _WaitingScreen extends StatefulWidget {
  const _WaitingScreen({required this.caller, required this.delay});

  final String caller;
  final Duration delay;

  @override
  State<_WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends State<_WaitingScreen> {
  Timer? _timer;
  late int _left = widget.delay.inSeconds;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) {
        t.cancel();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(builder: (_) => IncomingCallScreen(caller: widget.caller)),
        );
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121014),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Ringing in $_left s', style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 15)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Color(0xCCFFFFFF))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key, required this.caller});

  final String caller;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  @override
  void initState() {
    super.initState();
    _ringer.invokeMethod<void>('start').ignore();
  }

  @override
  void dispose() {
    _ringer.invokeMethod<void>('stop').ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CallBackground(
      child: Column(
        children: [
          const SizedBox(height: 64),
          _CallerHeader(name: widget.caller, status: 'Incoming call · Mobile'),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RoundButton(
                color: const Color(0xFFE5484D),
                icon: Icons.call_end,
                label: 'Decline',
                onTap: () => Navigator.pop(context),
              ),
              _RoundButton(
                color: const Color(0xFF30A46C),
                icon: Icons.call,
                label: 'Accept',
                onTap: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute<void>(builder: (_) => _InCallScreen(caller: widget.caller)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 72),
        ],
      ),
    );
  }
}

class _InCallScreen extends StatefulWidget {
  const _InCallScreen({required this.caller});

  final String caller;

  @override
  State<_InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<_InCallScreen> {
  final _watch = Stopwatch()..start();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _watch.elapsed.inSeconds;
    final time = '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
    return _CallBackground(
      child: Column(
        children: [
          const SizedBox(height: 64),
          _CallerHeader(name: widget.caller, status: time),
          const Spacer(),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CallTool(icon: Icons.mic_off, label: 'Mute'),
              _CallTool(icon: Icons.dialpad, label: 'Keypad'),
              _CallTool(icon: Icons.volume_up, label: 'Speaker'),
            ],
          ),
          const SizedBox(height: 48),
          _RoundButton(
            color: const Color(0xFFE5484D),
            icon: Icons.call_end,
            label: 'End',
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 72),
        ],
      ),
    );
  }
}

class _CallBackground extends StatelessWidget {
  const _CallBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF26222B), Color(0xFF121014)],
          ),
        ),
        child: SafeArea(
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}

class _CallerHeader extends StatelessWidget {
  const _CallerHeader({required this.name, required this.status});

  final String name;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Avatar(name: name, size: 96),
        const SizedBox(height: 20),
        Text(
          name,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        const SizedBox(height: 6),
        Text(status, style: const TextStyle(fontSize: 15, color: Color(0xB3FFFFFF))),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.color, required this.icon, required this.label, required this.onTap});

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(fontSize: 14, color: Color(0xCCFFFFFF))),
      ],
    );
  }
}

class _CallTool extends StatelessWidget {
  const _CallTool({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: const BoxDecoration(color: Color(0x1FFFFFFF), shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xB3FFFFFF))),
      ],
    );
  }
}
