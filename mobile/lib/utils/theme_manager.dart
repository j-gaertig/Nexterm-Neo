import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/app_ui.dart';
import 'app_themes.dart';

class ThemeManager extends ChangeNotifier {
  static const String _themeModeKey = 'themeMode';
  static const String _appThemeKey = 'appTheme';
  static const String _legacyUseDynamicColorKey = 'useDynamicColor';

  ThemeMode _themeMode;
  AppThemeDefinition _theme;

  ThemeMode get themeMode => _themeMode;
  AppThemeDefinition get theme => _theme;

  ThemeManager(ThemeMode themeMode, {AppThemeDefinition? theme})
    : _themeMode = themeMode,
      _theme = theme ?? AppThemes.graphite;

  static ThemeMode parseStoredThemeMode(String? storedMode) {
    switch (storedMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static Future<AppThemeDefinition> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final storedTheme = prefs.getString(_appThemeKey);
    if (storedTheme != null) return AppThemes.byId(storedTheme);

    // Migrate the old "Dynamic Color" switch to the Adaptive palette.
    final legacyDynamicColor = prefs.getBool(_legacyUseDynamicColorKey);
    return legacyDynamicColor == true ? AppThemes.adaptive : AppThemes.graphite;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _themeModeKey,
      mode.name,
    );
  }

  Future<void> setTheme(AppThemeDefinition theme) async {
    if (_theme.id == theme.id) return;
    _theme = theme;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _appThemeKey,
      theme.id,
    );
  }

  static const _pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    },
  );

  ColorScheme _buildScheme(
    Brightness brightness,
    ColorScheme? dynamicColorScheme,
  ) {
    if (_theme.usesSystemColor &&
        dynamicColorScheme != null &&
        dynamicColorScheme.brightness == brightness) {
      return dynamicColorScheme;
    }
    return _theme.palette(brightness).toColorScheme(brightness);
  }

  ThemeData _buildTheme(
    Brightness brightness,
    ColorScheme? dynamicColorScheme,
  ) {
    final scheme = _buildScheme(brightness, dynamicColorScheme);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      pageTransitionsTheme: _pageTransitions,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sheet),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: mutedAccent(scheme),
          foregroundColor: scheme.onSurface,
          disabledBackgroundColor: scheme.surfaceContainerHigh,
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: mutedAccent(scheme),
        foregroundColor: scheme.onSurface,
      ),
      // One snackbar style everywhere: floating, rounded, never full-width.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  ThemeData lightTheme({ColorScheme? dynamicColorScheme}) =>
      _buildTheme(Brightness.light, dynamicColorScheme);

  ThemeData darkTheme({ColorScheme? dynamicColorScheme}) =>
      _buildTheme(Brightness.dark, dynamicColorScheme);
}
