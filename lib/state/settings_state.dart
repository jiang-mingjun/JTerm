/// Persisted user preferences.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState extends ChangeNotifier {
  SettingsState._(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsState> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsState._(prefs);
  }

  // ---- terminal ----
  double get fontSize => _prefs.getDouble('fontSize') ?? 14.0;
  set fontSize(double v) {
    _prefs.setDouble('fontSize', v);
    notifyListeners();
  }

  String get fontFamily => _prefs.getString('fontFamily') ?? '';
  set fontFamily(String v) {
    _prefs.setString('fontFamily', v);
    notifyListeners();
  }

  // ---- appearance ----
  int get themeSeed => _prefs.getInt('themeSeed') ?? 0xFF0F766E;
  set themeSeed(int v) {
    _prefs.setInt('themeSeed', v);
    notifyListeners();
  }

  bool get darkMode => _prefs.getBool('darkMode') ?? true;
  set darkMode(bool v) {
    _prefs.setBool('darkMode', v);
    notifyListeners();
  }

  // ---- transfers ----
  String get downloadDir => _prefs.getString('downloadDir') ?? '';
  set downloadDir(String v) {
    _prefs.setString('downloadDir', v);
    notifyListeners();
  }

  String get terminalTheme => _prefs.getString('terminalTheme') ?? 'jterm-dark';
  set terminalTheme(String v) {
    _prefs.setString('terminalTheme', v);
    notifyListeners();
  }

  String get cursorStyle => _prefs.getString('cursorStyle') ?? 'block';
  set cursorStyle(String v) {
    _prefs.setString('cursorStyle', v);
    notifyListeners();
  }

  bool get copyOnSelect => _prefs.getBool('copyOnSelect') ?? true;
  set copyOnSelect(bool v) {
    _prefs.setBool('copyOnSelect', v);
    notifyListeners();
  }

  bool get visualBell => _prefs.getBool('visualBell') ?? true;
  set visualBell(bool v) {
    _prefs.setBool('visualBell', v);
    notifyListeners();
  }

  bool get logSessions => _prefs.getBool('logSessions') ?? false;
  set logSessions(bool v) {
    _prefs.setBool('logSessions', v);
    notifyListeners();
  }

  int get scrollbackLines => _prefs.getInt('scrollbackLines') ?? 10000;
  set scrollbackLines(int v) {
    _prefs.setInt('scrollbackLines', v);
    notifyListeners();
  }

  List<String> get sftpBookmarks =>
      _prefs.getStringList('sftpBookmarks') ?? const [];

  void toggleBookmark(String path) {
    final next = [...sftpBookmarks];
    if (next.contains(path)) {
      next.remove(path);
    } else {
      next.add(path);
    }
    _prefs.setStringList('sftpBookmarks', next);
    notifyListeners();
  }
}
