import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safeher/data/settings_store.dart';
import 'package:safeher/services/distress_checker.dart';
import 'package:safeher/services/scream_detector.dart';
import 'package:safeher/services/shake_detector.dart';

/// 100 ms of a 440 Hz tone at [amplitude] (0..1) as 16-bit PCM.
Uint8List tone(double amplitude, {int frames = 1}) {
  final n = LoudnessGate.sampleRate ~/ 10 * frames;
  final samples = Int16List(n);
  for (var i = 0; i < n; i++) {
    samples[i] = (math.sin(2 * math.pi * 440 * i / LoudnessGate.sampleRate) * amplitude * 32767).round();
  }
  return samples.buffer.asUint8List();
}

void main() {
  group('ShakeDetector', () {
    test('three strong shakes within 2 seconds trigger once', () {
      var fired = 0;
      final d = ShakeDetector(onTriggered: () => fired++);
      final t0 = DateTime(2026);
      for (final ms in [0, 400, 800]) {
        d.addSample(25, t0.add(Duration(milliseconds: ms)));
      }
      expect(fired, 1);
    });

    test('shakes spread over more than 2 seconds do not trigger', () {
      var fired = 0;
      final d = ShakeDetector(onTriggered: () => fired++);
      final t0 = DateTime(2026);
      for (final ms in [0, 1500, 3000]) {
        d.addSample(25, t0.add(Duration(milliseconds: ms)));
      }
      expect(fired, 0);
    });

    test('walking-level movement and one long jolt do not count', () {
      var fired = 0;
      final d = ShakeDetector(onTriggered: () => fired++)
        ..threshold = ShakeDetector.thresholdFor(ShakeSensitivity.medium);
      final t0 = DateTime(2026);
      // Gentle bumps every 100 ms for 2 s.
      for (var ms = 0; ms < 2000; ms += 100) {
        d.addSample(8, t0.add(Duration(milliseconds: ms)));
      }
      // One jolt that stays above the line for 200 ms is a single shake, not three.
      for (var ms = 0; ms < 200; ms += 20) {
        d.addSample(30, t0.add(Duration(milliseconds: 3000 + ms)));
      }
      expect(fired, 0);
    });
  });

  group('LoudnessGate', () {
    test('quiet room does not spike; a sudden loud sound does', () {
      final g = LoudnessGate();
      for (var i = 0; i < 30; i++) {
        g.add(tone(0.01)); // about -43 dBFS
      }
      expect(g.spike, isFalse);
      g.add(tone(0.6, frames: 4)); // about -7 dBFS
      expect(g.spike, isTrue);
      expect(g.clipPcm().length, LoudnessGate.keepFrames * LoudnessGate.frameBytes);
    });

    test('frames split across stream chunks are reassembled', () {
      final g = LoudnessGate();
      final pcm = tone(0.1, frames: 2);
      expect(g.add(Uint8List.sublistView(pcm, 0, 1000)), 0);
      expect(g.add(Uint8List.sublistView(pcm, 1000)), 2);
    });
  });

  test('pcm16ToWav writes a valid 16 kHz mono header', () {
    final wav = pcm16ToWav(Uint8List(3200));
    final b = ByteData.sublistView(wav);
    expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
    expect(b.getUint32(24, Endian.little), 16000);
    expect(b.getUint16(22, Endian.little), 1);
    expect(b.getUint32(40, Endian.little), 3200);
    expect(wav.length, 44 + 3200);
  });

  group('DistressChecker', () {
    test('reads Gemini structured output', () async {
      final client = MockClient((req) async {
        expect(req.headers['x-goog-api-key'], 'k');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['generationConfig']['responseMimeType'], 'application/json');
        final answer = jsonEncode({
          'distress': true,
          'kind': 'scream',
          'confidence': 0.93,
          'heard': 'A woman screaming',
        });
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': answer},
                  ],
                },
              },
            ],
          }),
          200,
        );
      });
      final v = await DistressChecker(client: client, apiKey: 'k').check(pcm16ToWav(Uint8List(3200)));
      expect(v!.distress, isTrue);
      expect(v.kind, 'scream');
      expect(v.heard, 'A woman screaming');
    });

    test('returns null on errors instead of guessing', () async {
      final client = MockClient((_) async => http.Response('{"error":{}}', 429));
      expect(await DistressChecker(client: client, apiKey: 'k').check(Uint8List(0)), isNull);
    });

    test('without a key it does not call the network', () async {
      final client = MockClient((_) async => fail('should not be called'));
      expect(await DistressChecker(client: client, apiKey: '').check(Uint8List(0)), isNull);
    });
  });
}
