import 'dart:convert';

import 'package:http/http.dart' as http;

/// Why a Gemini call gave no answer, so screens can say something useful.
enum GeminiFailure { noKey, busy, network, badAnswer }

class GeminiException implements Exception {
  const GeminiException(this.failure);

  final GeminiFailure failure;
}

/// One model to try, with the thinking setting that model accepts.
class GeminiModel {
  const GeminiModel(this.name, this.thinking);

  final String name;
  final Map<String, Object> thinking;
}

/// Minimal Gemini REST client that asks for JSON matching a schema.
///
/// The key comes from `--dart-define-from-file=env/gemini.json` and is never committed.
class GeminiClient {
  GeminiClient({http.Client? client, String? apiKey})
    : _client = client ?? http.Client(),
      _apiKey = apiKey ?? const String.fromEnvironment('GEMINI_API_KEY');

  final http.Client _client;
  final String _apiKey;

  bool get configured => _apiKey.isNotEmpty;

  /// Tries [models] in order; a rate limit or overload on one falls through to the next.
  Future<Map<String, dynamic>> generateJson({
    required List<GeminiModel> models,
    required List<Map<String, Object>> parts,
    required Map<String, Object> schema,
    double temperature = 0,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!configured) throw const GeminiException(GeminiFailure.noKey);
    var failure = GeminiFailure.network;
    for (final m in models) {
      final body = jsonEncode({
        'contents': [
          {'parts': parts},
        ],
        'generationConfig': {
          'responseMimeType': 'application/json',
          'responseSchema': schema,
          'temperature': temperature,
          'thinkingConfig': m.thinking,
        },
      });
      final http.Response res;
      try {
        res = await _client
            .post(
              Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/${m.name}:generateContent'),
              headers: {'x-goog-api-key': _apiKey, 'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(timeout);
      } catch (_) {
        failure = GeminiFailure.network;
        continue;
      }
      if (res.statusCode == 429 || res.statusCode >= 500) {
        failure = GeminiFailure.busy;
        continue;
      }
      try {
        // Always UTF-8: Bangla answers must not depend on the response's charset header.
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final text = data['candidates'][0]['content']['parts'][0]['text'] as String;
        return jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        failure = GeminiFailure.badAnswer;
      }
    }
    throw GeminiException(failure);
  }
}

Map<String, Object> inlineData(String mimeType, List<int> bytes) => {
  'inline_data': {'mime_type': mimeType, 'data': base64Encode(bytes)},
};
