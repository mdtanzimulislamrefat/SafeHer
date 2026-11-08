import 'package:flutter/widgets.dart' show StringCharacters;

/// A person in the user's Trusted Circle, with what they are allowed to receive.
class TrustedContact {
  const TrustedContact({
    required this.id,
    required this.name,
    required this.phone,
    this.relation = '',
    this.getsSos = true,
    this.getsJourneys = true,
    this.getsLocation = true,
  });

  final String id;
  final String name;

  /// Stored in E.164 form, e.g. +8801712345678.
  final String phone;
  final String relation;
  final bool getsSos;
  final bool getsJourneys;
  final bool getsLocation;

  String get initial => name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();

  /// Short "what they get" line, e.g. "SOS · journeys · live location".
  String get permissionSummary {
    final parts = [if (getsSos) 'SOS', if (getsJourneys) 'journeys', if (getsLocation) 'location'];
    return parts.isEmpty ? 'Nothing yet' : parts.join(' · ');
  }

  /// Phone with the middle digits hidden, for screens others might see.
  String get maskedPhone {
    if (phone.length < 8) return phone;
    return '${phone.substring(0, 8)} •••${phone.substring(phone.length - 3)}';
  }

  TrustedContact copyWith({
    String? name,
    String? phone,
    String? relation,
    bool? getsSos,
    bool? getsJourneys,
    bool? getsLocation,
  }) {
    return TrustedContact(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      relation: relation ?? this.relation,
      getsSos: getsSos ?? this.getsSos,
      getsJourneys: getsJourneys ?? this.getsJourneys,
      getsLocation: getsLocation ?? this.getsLocation,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'relation': relation,
    'getsSos': getsSos,
    'getsJourneys': getsJourneys,
    'getsLocation': getsLocation,
  };

  factory TrustedContact.fromJson(Map<String, dynamic> json) {
    return TrustedContact(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      relation: json['relation'] as String? ?? '',
      getsSos: json['getsSos'] as bool? ?? true,
      getsJourneys: json['getsJourneys'] as bool? ?? true,
      getsLocation: json['getsLocation'] as bool? ?? true,
    );
  }
}

/// Turns what the user typed into E.164, or returns null if it is not a phone number.
///
/// Accepts Bangladeshi mobiles in local form (01712345678) and any number
/// already written with a country code (+8801712345678, +447700900123).
String? normalizePhone(String input) {
  final digits = input.replaceAll(RegExp(r'[\s\-()]'), '');
  if (RegExp(r'^01[3-9]\d{8}$').hasMatch(digits)) return '+88$digits';
  if (RegExp(r'^8801[3-9]\d{8}$').hasMatch(digits)) return '+$digits';
  if (RegExp(r'^\+\d{8,15}$').hasMatch(digits)) return digits;
  return null;
}
