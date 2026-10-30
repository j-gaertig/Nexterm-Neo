import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NavigationBarStyle { floating, classic }

class NavigationBarSettings extends ChangeNotifier {
  static const String _styleKey = 'navigation_bar_style';

  NavigationBarStyle _style;

  NavigationBarStyle get style => _style;
  bool get useFloating => _style == NavigationBarStyle.floating;

  NavigationBarSettings._(this._style);

  static Future<NavigationBarSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_styleKey);
    final style = NavigationBarStyle.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => NavigationBarStyle.floating,
    );
    return NavigationBarSettings._(style);
  }

  Future<void> setUseFloating(bool value) {
    return setStyle(
      value ? NavigationBarStyle.floating : NavigationBarStyle.classic,
    );
  }

  Future<void> setStyle(NavigationBarStyle style) async {
    if (_style == style) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = await prefs.setString(_styleKey, style.name);
    if (stored && _style != style) {
      _style = style;
      notifyListeners();
    }
  }
}
