import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'trusted_contact.dart';

/// Keeps the Trusted Circle on this phone only.
class ContactsStore extends ChangeNotifier {
  ContactsStore(this._prefs) {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      final list = jsonDecode(raw) as List<dynamic>;
      _contacts.addAll(list.map((e) => TrustedContact.fromJson(e as Map<String, dynamic>)));
    }
  }

  static const _key = 'trusted_contacts_v1';
  final SharedPreferences _prefs;
  final List<TrustedContact> _contacts = [];

  List<TrustedContact> get all => List.unmodifiable(_contacts);
  List<TrustedContact> get sosRecipients => _contacts.where((c) => c.getsSos).toList();

  TrustedContact? byId(String id) {
    for (final c in _contacts) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> save(TrustedContact contact) async {
    final i = _contacts.indexWhere((c) => c.id == contact.id);
    if (i == -1) {
      _contacts.add(contact);
    } else {
      _contacts[i] = contact;
    }
    await _persist();
  }

  Future<void> remove(String id) async {
    _contacts.removeWhere((c) => c.id == id);
    await _persist();
  }

  Future<void> _persist() async {
    notifyListeners();
    await _prefs.setString(_key, jsonEncode(_contacts.map((c) => c.toJson()).toList()));
  }
}
