import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Play/pause card for a saved voice note, as in the v2 report design.
class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({super.key, required this.path});

  final String path;

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription<Object?>>[];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _subs.addAll([
      _player.onPositionChanged.listen((p) => setState(() => _position = p)),
      _player.onDurationChanged.listen((d) => setState(() => _duration = d)),
      _player.onPlayerStateChanged.listen((s) => setState(() => _playing = s == PlayerState.playing)),
      _player.onPlayerComplete.listen((_) => setState(() => _position = Duration.zero)),
    ]);
    _player.setSourceDeviceFile(widget.path);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  static String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds == 0 ? 0.0 : _position.inMilliseconds / _duration.inMilliseconds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SafeColors.card,
        border: Border.all(color: SafeColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          IconButton.filled(
            tooltip: _playing ? 'Pause voice note' : 'Play voice note',
            style: IconButton.styleFrom(backgroundColor: SafeColors.plum),
            onPressed: () => _playing ? _player.pause() : _player.resume(),
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
              backgroundColor: SafeColors.line,
              color: SafeColors.plum,
            ),
          ),
          const SizedBox(width: 12),
          Text(_fmt(_playing || _position > Duration.zero ? _position : _duration), style: SafeText.caption),
        ],
      ),
    );
  }
}
