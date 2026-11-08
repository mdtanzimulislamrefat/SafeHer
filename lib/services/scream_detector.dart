import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'distress_checker.dart';

/// Watches loudness only. Pure Dart so it can be tested without a microphone.
///
/// Audio arrives as 16-bit mono PCM at 16 kHz and is cut into 100 ms frames.
/// A spike is 3 loud frames within the last 6 (~300 ms of a 600 ms window).
class LoudnessGate {
  static const sampleRate = 16000;
  static const frameBytes = sampleRate ~/ 10 * 2; // 100 ms of 16-bit samples
  static const keepFrames = 25; // 2.5 s: 1.5 s before the spike + 1 s after

  /// Never louder-than-this counts, however quiet the room (dBFS).
  double absoluteFloor = -24;

  /// How far above the room's usual level a frame must be (dB).
  double aboveAmbient = 18;

  double ambient = -50;
  double lastLevel = -90;
  final List<Uint8List> _frames = [];
  final List<bool> _loud = [];
  final BytesBuilder _pending = BytesBuilder(copy: false);

  /// Feeds raw PCM; returns how many complete frames were added.
  int add(Uint8List pcm) {
    _pending.add(pcm);
    final all = _pending.takeBytes();
    var offset = 0;
    var added = 0;
    while (all.length - offset >= frameBytes) {
      _addFrame(Uint8List.sublistView(all, offset, offset + frameBytes));
      offset += frameBytes;
      added++;
    }
    if (offset < all.length) _pending.add(Uint8List.sublistView(all, offset));
    return added;
  }

  void _addFrame(Uint8List frame) {
    final level = dbfs(frame);
    lastLevel = level;
    final loud = level > math.max(absoluteFloor, ambient + aboveAmbient);
    // Learn the room slowly, and only from ordinary frames, so a scream doesn't raise the bar.
    if (!loud) ambient = ambient * 0.97 + level * 0.03;
    _frames.add(Uint8List.fromList(frame));
    _loud.add(loud);
    if (_frames.length > keepFrames) {
      _frames.removeAt(0);
      _loud.removeAt(0);
    }
  }

  bool get spike {
    final recent = _loud.length < 6 ? _loud : _loud.sublist(_loud.length - 6);
    return recent.where((l) => l).length >= 3;
  }

  /// Loud frames in the whole buffer; used when Gemini can't be reached.
  int get loudFrameCount => _loud.where((l) => l).length;

  Uint8List clipPcm() {
    final b = BytesBuilder(copy: false);
    for (final f in _frames) {
      b.add(f);
    }
    return b.toBytes();
  }

  void clearLoud() {
    for (var i = 0; i < _loud.length; i++) {
      _loud[i] = false;
    }
  }

  static double dbfs(Uint8List frame) {
    final samples = Int16List.view(frame.buffer, frame.offsetInBytes, frame.lengthInBytes ~/ 2);
    var sum = 0.0;
    for (final s in samples) {
      sum += s * s;
    }
    final rms = math.sqrt(sum / samples.length) / 32768;
    return rms <= 0 ? -90 : 20 * math.log(rms) / math.ln10;
  }
}

enum ScreamStatus { off, listening, checking, coolingDown, needsInternet, micError }

/// Live state for the Home row and the test sheet.
class ScreamState {
  const ScreamState({
    this.status = ScreamStatus.off,
    this.level = -90,
    this.ambient = -50,
    this.lastVerdict,
    this.lastCheckedAt,
  });

  final ScreamStatus status;
  final double level;
  final double ambient;
  final DistressVerdict? lastVerdict;
  final DateTime? lastCheckedAt;

  ScreamState copyWith({
    ScreamStatus? status,
    double? level,
    double? ambient,
    DistressVerdict? lastVerdict,
    DateTime? lastCheckedAt,
  }) {
    return ScreamState(
      status: status ?? this.status,
      level: level ?? this.level,
      ambient: ambient ?? this.ambient,
      lastVerdict: lastVerdict ?? this.lastVerdict,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }
}

/// Microphone → loudness gate → (only on a spike) Gemini → maybe SOS.
///
/// Nothing is recorded to disk. Audio leaves the phone only as a 2.5 s clip after a loud spike.
class ScreamDetector {
  ScreamDetector({required this.onDistress, DistressChecker? checker}) : _checker = checker ?? DistressChecker();

  /// Called with Gemini's verdict, or null for the offline fallback.
  final void Function(DistressVerdict? verdict) onDistress;
  final DistressChecker _checker;

  static const minConfidence = 0.6;
  static const cooldown = Duration(seconds: 8);

  /// Without internet, only a long, very loud sound (≥ 1.2 s of the clip) starts the countdown.
  static const offlineLoudFrames = 12;

  final state = ValueNotifier(const ScreamState());
  final _gate = LoudnessGate();
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _sub;
  int _framesAfterSpike = -1;
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);

  bool get running => _sub != null;

  Future<void> start() async {
    if (_sub != null) return;
    final rec = AudioRecorder();
    try {
      if (!await rec.hasPermission(request: false)) {
        await rec.dispose();
        state.value = state.value.copyWith(status: ScreamStatus.micError);
        return;
      }
      final stream = await rec.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: LoudnessGate.sampleRate, numChannels: 1),
      );
      _recorder = rec;
      _sub = stream.listen(_onPcm, onError: (_) => stop(error: true));
      state.value = state.value.copyWith(status: ScreamStatus.listening);
    } catch (_) {
      await rec.dispose();
      state.value = state.value.copyWith(status: ScreamStatus.micError);
    }
  }

  Future<void> stop({bool error = false}) async {
    await _sub?.cancel();
    _sub = null;
    final rec = _recorder;
    _recorder = null;
    await rec?.stop();
    await rec?.dispose();
    _framesAfterSpike = -1;
    state.value = state.value.copyWith(status: error ? ScreamStatus.micError : ScreamStatus.off, level: -90);
  }

  void _onPcm(Uint8List pcm) {
    final added = _gate.add(pcm);
    if (added == 0) return;
    final s = state.value;
    final now = DateTime.now();
    var status = s.status;
    if (status == ScreamStatus.coolingDown && now.isAfter(_quietUntil)) status = ScreamStatus.listening;
    state.value = s.copyWith(level: _gate.lastLevel, ambient: _gate.ambient, status: status);

    if (_framesAfterSpike >= 0) {
      _framesAfterSpike += added;
      if (_framesAfterSpike >= 10) {
        _framesAfterSpike = -1;
        _check();
      }
      return;
    }
    if (status == ScreamStatus.listening && _gate.spike) {
      _framesAfterSpike = 0; // keep listening 1 s so the clip includes what comes next
    }
  }

  Future<void> _check() async {
    final loudFrames = _gate.loudFrameCount;
    final wav = pcm16ToWav(_gate.clipPcm());
    _gate.clearLoud();
    state.value = state.value.copyWith(status: ScreamStatus.checking);

    final verdict = await _checker.check(wav);
    _quietUntil = DateTime.now().add(cooldown);
    if (!running) return;
    if (verdict == null) {
      state.value = state.value.copyWith(status: ScreamStatus.needsInternet);
      if (loudFrames >= offlineLoudFrames) onDistress(null);
    } else {
      state.value = state.value.copyWith(
        status: ScreamStatus.coolingDown,
        lastVerdict: verdict,
        lastCheckedAt: DateTime.now(),
      );
      if (verdict.distress && verdict.confidence >= minConfidence) onDistress(verdict);
    }
    if (state.value.status == ScreamStatus.needsInternet) {
      // Keep listening; the next spike will try Gemini again.
      Future<void>.delayed(cooldown, () {
        if (running && state.value.status == ScreamStatus.needsInternet) {
          state.value = state.value.copyWith(status: ScreamStatus.listening);
        }
      });
    }
  }
}
