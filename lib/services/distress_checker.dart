import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Gemini's verdict on one short audio clip.
class DistressVerdict {
  const DistressVerdict({required this.distress, required this.kind, required this.confidence, required this.heard});

  final bool distress;

  /// scream, call_for_help, shout, speech, noise or other.
  final String kind;
  final double confidence;

  /// Gemini's short description of the clip, shown to the user so the decision is explainable.
  final String heard;

  factory DistressVerdict.fromJson(Map<String, dynamic> j) => DistressVerdict(
    distress: j['distress'] as bool? ?? false,
    kind: j['kind'] as String? ?? 'other',
    confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
    heard: j['heard'] as String? ?? '',
  );
}

/// Asks Gemini whether a loud clip is someone in distress.
///
/// Only clips that already crossed the loudness gate are sent, so a normal day
/// makes very few requests. Audio is never written to disk.
class DistressChecker {
  DistressChecker({http.Client? client, String? apiKey})
    : _client = client ?? http.Client(),
      _apiKey = apiKey ?? const String.fromEnvironment('GEMINI_API_KEY');

  // Picked by measurement: ~2-3 s per clip with minimal thinking, and correct on test clips.
  static const model = 'gemini-flash-lite-latest';
  static const timeout = Duration(seconds: 8);

  final http.Client _client;
  final String _apiKey;

  bool get configured => _apiKey.isNotEmpty;

  static const _prompt =
      'You are the safety check inside a personal-safety app in Bangladesh. The phone heard a sudden loud '
      'sound; this is a short clip of it. Decide whether it sounds like a person in distress: screaming, '
      "shrieking in fear, or shouting for help in any language (e.g. 'help', 'bachao', 'বাঁচাও'). "
      'Normal loud talk, laughter, cheering, music, traffic, horns or TV are NOT distress. '
      "Be careful: a false alarm alerts the user's family.";

  static const _schema = {
    'type': 'OBJECT',
    'properties': {
      'distress': {'type': 'BOOLEAN'},
      'kind': {
        'type': 'STRING',
        'enum': ['scream', 'call_for_help', 'shout', 'speech', 'noise', 'other'],
      },
      'confidence': {'type': 'NUMBER'},
      'heard': {'type': 'STRING', 'description': 'Under 12 words: what the clip contains.'},
    },
    'required': ['distress', 'kind', 'confidence', 'heard'],
  };

  /// Returns null when Gemini can't be reached or answers badly; callers decide what that means.
  Future<DistressVerdict?> check(Uint8List wav) async {
    if (!configured) return null;
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'inline_data': {'mime_type': 'audio/wav', 'data': base64Encode(wav)},
            },
            {'text': _prompt},
          ],
        },
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'responseSchema': _schema,
        'temperature': 0,
        'thinkingConfig': {'thinkingLevel': 'minimal'},
      },
    });
    try {
      final res = await _client
          .post(
            Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
            headers: {'x-goog-api-key': _apiKey, 'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(timeout);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final text = data['candidates'][0]['content']['parts'][0]['text'] as String;
      return DistressVerdict.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

/// Wraps 16-bit mono PCM in a WAV header so Gemini can read it.
Uint8List pcm16ToWav(Uint8List pcm, {int sampleRate = 16000}) {
  final header = ByteData(44);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(pcm))
      .toBytes();
}
