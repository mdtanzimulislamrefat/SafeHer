import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/trusted_contact.dart';
import '../services/sos_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'sos_status_screen.dart';

/// Five seconds to cancel an accidental trigger. Cancelling sends nothing.
class SosCountdownScreen extends StatefulWidget {
  const SosCountdownScreen({super.key, required this.trigger, required this.recipients, this.detail, this.seconds = 5});

  final SosTrigger trigger;

  /// Why it started, e.g. what Gemini heard. Helps her judge a false alarm quickly.
  final String? detail;
  final List<TrustedContact> recipients;
  final int seconds;

  @override
  State<SosCountdownScreen> createState() => _SosCountdownScreenState();
}

class _SosCountdownScreenState extends State<SosCountdownScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.seconds),
  )..forward();
  late int _left = widget.seconds;
  late final SosController _controller;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _controller = context.read<SosController>()..countingDown = true;
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) {
        t.cancel();
        _fire();
      } else {
        HapticFeedback.mediumImpact();
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _controller.countingDown = false;
    _tick?.cancel();
    _ring.dispose();
    super.dispose();
  }

  void _fire() {
    // Not awaited: the status screen shows progress as each SMS resolves.
    context.read<SosController>().dispatch(trigger: widget.trigger, recipients: widget.recipients);
    Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => const SosStatusScreen()));
  }

  void _cancel() {
    _tick?.cancel();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.recipients.map((c) => c.name).toList();
    const white = Colors.white;
    return PopScope(
      // Back button counts as cancel.
      onPopInvokedWithResult: (didPop, _) => _tick?.cancel(),
      child: Scaffold(
        backgroundColor: SafeColors.redDeep,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 36, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Alerting your circle', style: SafeText.heading(28, color: white)),
                const SizedBox(height: 4),
                const Text(
                  'আপনার বিশ্বস্ত মানুষদের জানানো হচ্ছে',
                  style: TextStyle(fontSize: 15, color: Color(0xCCFFFFFF)),
                ),
                const Spacer(),
                Center(
                  child: SizedBox(
                    width: 232,
                    height: 232,
                    child: AnimatedBuilder(
                      animation: _ring,
                      builder: (context, child) => CustomPaint(painter: _RingPainter(1 - _ring.value), child: child),
                      child: Semantics(
                        liveRegion: true,
                        label: 'Sending in $_left seconds',
                        excludeSemantics: true,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('$_left', style: SafeText.heading(104, color: white).copyWith(height: 1)),
                            const Text('seconds', style: TextStyle(fontSize: 13, color: Color(0xBFFFFFFF))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    AvatarStack(names: names, size: 30, ring: SafeColors.redDeep),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        names.join(', '),
                        style: const TextStyle(fontSize: 15, color: white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Started by ${widget.trigger.label}',
                  style: const TextStyle(fontSize: 13, color: Color(0xBFFFFFFF)),
                ),
                if (widget.detail != null && widget.detail!.isNotEmpty)
                  Text(
                    'Gemini heard: “${widget.detail}”',
                    style: const TextStyle(fontSize: 13, color: Color(0xBFFFFFFF)),
                  ),
                const SizedBox(height: 28),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: white,
                    foregroundColor: SafeColors.redDeep,
                    minimumSize: const Size.fromHeight(64),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    textStyle: const TextStyle(fontFamily: 'HindSiliguri', fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  onPressed: _cancel,
                  child: const Text("I'm okay — cancel"),
                ),
                const SizedBox(height: 10),
                const Center(
                  child: Text(
                    'বাতিল করলে কিছুই পাঠানো হবে না',
                    style: TextStyle(fontSize: 13, color: Color(0xB3FFFFFF)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.remaining);

  final double remaining;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, 0, math.pi * 2, false, paint..color = const Color(0x2EFFFFFF));
    canvas.drawArc(arc, -math.pi / 2, math.pi * 2 * remaining, false, paint..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.remaining != remaining;
}
