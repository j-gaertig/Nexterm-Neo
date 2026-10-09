import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-local preferences (device-only, no server involved).
class AppSettings extends ChangeNotifier {
  static const _kThemeMode = 'nexterm_v2.theme_mode';
  static const _kAccent = 'nexterm_v2.accent_seed';
  static const _kTermCursor = 'nexterm_v2.term_cursor';
  static const _kTermFont = 'nexterm_v2.term_font_size';
  static const _kPwHint = 'nexterm_v2.term_password_hint';
  static const _kShowHidden = 'nexterm_v2.sftp_show_hidden';
  static const _kConfirmDelete = 'nexterm_v2.sftp_confirm_delete';
  static const _kGridDefault = 'nexterm_v2.servers_grid_default';
  static const _kMonRefresh = 'nexterm_v2.monitoring_auto_refresh';
  static const _kMonInterval = 'nexterm_v2.monitoring_interval';

  ThemeMode themeMode = ThemeMode.system;
  int accentSeed = 0xFF3F51B5; // Indigo.

  /// Terminal cursor: block, underline or bar.
  String terminalCursor = 'block';
  double terminalFontSize = 14;
  bool terminalPasswordHint = true;
  bool sftpShowHidden = false;
  bool sftpConfirmDelete = true;
  bool serversGridDefault = false;
  bool monitoringAutoRefresh = true;
  int monitoringIntervalSec = 30;

  static const List<int> accentChoices = [
    0xFF3F51B5, // Indigo
    0xFF1565C0, // Blue
    0xFF00897B, // Teal
    0xFF2E7D32, // Green
    0xFFEF6C00, // Orange
    0xFFC62828, // Red
    0xFF6A1B9A, // Purple
  ];

  static Future<AppSettings> load() async {
    final s = AppSettings();
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString(_kThemeMode);
      s.themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == mode,
        orElse: () => ThemeMode.system,
      );
      s.accentSeed =
          prefs.getInt(_kAccent) ?? 0xFF3F51B5;
      final cursor = prefs.getString(_kTermCursor);
      s.terminalCursor = const ['block', 'underline', 'bar']
              .contains(cursor)
          ? cursor!
          : 'block';
      s.terminalFontSize =
          (prefs.getDouble(_kTermFont) ?? 14).clamp(10.0, 24.0);
      s.terminalPasswordHint = prefs.getBool(_kPwHint) ?? true;
      s.sftpShowHidden = prefs.getBool(_kShowHidden) ?? false;
      s.sftpConfirmDelete = prefs.getBool(_kConfirmDelete) ?? true;
      s.serversGridDefault = prefs.getBool(_kGridDefault) ?? false;
      s.monitoringAutoRefresh = prefs.getBool(_kMonRefresh) ?? true;
      s.monitoringIntervalSec =
          (prefs.getInt(_kMonInterval) ?? 30).clamp(15, 300);
    } catch (_) {}
    return s;
  }

  Future<void> _save(Future<void> Function(SharedPreferences) write) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await write(prefs);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await _save((p) => p.setString(_kThemeMode, mode.name));
  }

  Future<void> setAccentSeed(int seed) async {
    accentSeed = seed;
    await _save((p) => p.setInt(_kAccent, seed));
  }

  static const List<String> terminalCursors = [
    'block',
    'underline',
    'bar',
  ];

  Future<void> setTerminalCursor(String cursor) async {
    if (!terminalCursors.contains(cursor)) return;
    terminalCursor = cursor;
    await _save((p) => p.setString(_kTermCursor, cursor));
  }

  Future<void> setTerminalFontSize(double size) async {
    terminalFontSize = size.clamp(10.0, 24.0);
    await _save((p) => p.setDouble(_kTermFont, terminalFontSize));
  }

  Future<void> setTerminalPasswordHint(bool value) async {
    terminalPasswordHint = value;
    await _save((p) => p.setBool(_kPwHint, value));
  }

  Future<void> setSftpShowHidden(bool value) async {
    sftpShowHidden = value;
    await _save((p) => p.setBool(_kShowHidden, value));
  }

  Future<void> setSftpConfirmDelete(bool value) async {
    sftpConfirmDelete = value;
    await _save((p) => p.setBool(_kConfirmDelete, value));
  }

  Future<void> setServersGridDefault(bool value) async {
    serversGridDefault = value;
    await _save((p) => p.setBool(_kGridDefault, value));
  }

  Future<void> setMonitoringAutoRefresh(bool value) async {
    monitoringAutoRefresh = value;
    await _save((p) => p.setBool(_kMonRefresh, value));
  }

  Future<void> setMonitoringInterval(int seconds) async {
    monitoringIntervalSec = seconds.clamp(15, 300);
    await _save((p) => p.setInt(_kMonInterval, monitoringIntervalSec));
  }
}
