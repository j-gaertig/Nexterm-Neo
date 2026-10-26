import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScreenLockSettings extends ChangeNotifier {
  static const String _enabledKey = 'screen_lock_enabled';

  bool _enabled;

  bool get enabled => _enabled;

  ScreenLockSettings._(this._enabled);

  static Future<ScreenLockSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ScreenLockSettings._(prefs.getBool(_enabledKey) ?? false);
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = await prefs.setBool(_enabledKey, value);
    if (stored && _enabled != value) {
      _enabled = value;
      notifyListeners();
    }
  }
}
