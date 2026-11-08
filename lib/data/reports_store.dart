import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'incident_report.dart';

/// The private library. Reports and voice notes stay on this phone.
class ReportsStore extends ChangeNotifier {
  ReportsStore(this._prefs) {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      _reports.addAll(
        (jsonDecode(raw) as List<dynamic>).map((e) => IncidentReport.fromJson(e as Map<String, dynamic>)),
      );
    }
  }

  static const _key = 'incident_reports_v1';
  final SharedPreferences _prefs;
  final List<IncidentReport> _reports = [];

  /// Newest first.
  List<IncidentReport> get all => List.unmodifiable(_reports.reversed);

  Future<void> save(IncidentReport report) async {
    final i = _reports.indexWhere((r) => r.id == report.id);
    if (i == -1) {
      _reports.add(report);
    } else {
      _reports[i] = report;
    }
    await _persist();
  }

  /// Removes the record and its voice note file.
  Future<void> delete(IncidentReport report) async {
    _reports.removeWhere((r) => r.id == report.id);
    final path = report.audioPath;
    if (path != null) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // Already gone; the record is what matters.
      }
    }
    await _persist();
  }

  Future<void> _persist() async {
    notifyListeners();
    await _prefs.setString(_key, jsonEncode(_reports.map((r) => r.toJson()).toList()));
  }
}
