import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// What we honestly know about one SMS. There is deliberately no "delivered".
enum SmsOutcome {
  queued,
  sending,

  /// The radio accepted it and it left this phone.
  sent,

  /// No answer from the radio yet (e.g. no signal); Android may still send it.
  waiting,
  failed,

  /// We opened the user's SMS app; we can't know if she pressed send.
  handedToSmsApp,
}

class SmsResult {
  const SmsResult(this.outcome, {this.via = '', this.reason = ''});

  final SmsOutcome outcome;

  /// Carrier of the SIM that sent it, e.g. "Grameenphone"; empty if unknown.
  final String via;

  /// Why it failed: "no_service", "limit", "no_sim" or "error".
  final String reason;
}

class SmsSender {
  static const _channel = MethodChannel('safeher/sms');

  /// Sends directly through the SIM, trying other SIMs if the default one fails.
  Future<SmsResult> send(String phone, String message) async {
    try {
      final raw = await _channel.invokeMethod<String>('send', {'phone': phone, 'message': message}) ?? '';
      final [status, detail] = [...raw.split('|'), '', ''].take(2).toList();
      return switch (status) {
        'sent' => SmsResult(SmsOutcome.sent, via: detail),
        'waiting' => SmsResult(SmsOutcome.waiting, via: detail),
        _ => SmsResult(SmsOutcome.failed, reason: detail),
      };
    } on PlatformException {
      return const SmsResult(SmsOutcome.failed, reason: 'error');
    }
  }

  /// Fallback without permission: opens the SMS app with all numbers and the text filled in.
  Future<bool> openSmsApp(List<String> phones, String message) {
    // queryParameters would turn spaces into '+', which some SMS apps show literally.
    final uri = Uri(scheme: 'sms', path: phones.join(','), query: 'body=${Uri.encodeComponent(message)}');
    return launchUrl(uri);
  }
}
