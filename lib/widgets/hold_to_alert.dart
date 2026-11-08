import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// The SOS bar. A tap does nothing; holding for [holdFor] fires [onTriggered].
class HoldToAlert extends StatefulWidget {
  const HoldToAlert({super.key, required this.onTriggered, this.holdFor = const Duration(seconds: 2)});

  final VoidCallback onTriggered;
  final Duration holdFor;

  @override
  State<HoldToAlert> createState() => _HoldToAlertState();
}

class _HoldToAlertState extends State<HoldToAlert> with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(vsync: this, duration: widget.holdFor)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        _progress.value = 0;
        widget.onTriggered();
      }
    });

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _start() {
    HapticFeedback.selectionClick();
    _progress.forward(from: 0);
  }

  void _release() {
    if (_progress.isAnimating) _progress.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'SOS. Hold for two seconds to alert your circle.',
      // Screen-reader users get a direct action instead of a timed hold.
      onLongPress: widget.onTriggered,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => _start(),
        onTapUp: (_) => _release(),
        onTapCancel: _release,
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            return Container(
              height: 76,
              decoration: BoxDecoration(
                color: SafeColors.red,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [BoxShadow(color: Color(0x47D7263D), blurRadius: 18, offset: Offset(0, 6))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Fill grows left to right while held.
                  FractionallySizedBox(
                    widthFactor: _progress.value,
                    child: Container(color: SafeColors.redDeep),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: SafeColors.redDeep, borderRadius: BorderRadius.circular(18)),
                          child: Text('SOS', style: SafeText.heading(18, color: Colors.white)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _progress.value > 0 ? 'Keep holding…' : 'Hold to alert your circle',
                                style: const TextStyle(
                                  fontSize: 17,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const Text(
                                'চেপে ধরে রাখুন · ২ সেকেন্ড',
                                style: TextStyle(fontSize: 13, color: Color(0xE6FFFFFF)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
