import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/app_themes.dart';
import 'package:nexterm/utils/theme_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ships the renamed palettes in a stable order', () {
    expect(AppThemes.all.map((theme) => theme.label), [
      'Graphite',
      'Adaptive',
      'Blossom',
      'Meadow',
      'Tide',
      'Copper',
      'Aurora',
    ]);
    expect(AppThemes.all.map((theme) => theme.id).toSet(), hasLength(7));
  });

  test('starts with Graphite and applies its published colors', () {
    final manager = ThemeManager(ThemeMode.dark);

    expect(manager.theme.id, AppThemes.graphite.id);
    final scheme = manager.darkTheme().colorScheme;
    expect(scheme.brightness, Brightness.dark);
    expect(scheme.primary, const Color(0xFF346BF1));
    expect(scheme.surface, const Color(0xFF0A0A0A));
    expect(scheme.onSurface, const Color(0xFFF5F5F5));
  });

  test('persists and applies a selected palette', () async {
    final manager = ThemeManager(ThemeMode.light);

    await manager.setTheme(AppThemes.blossom);

    expect(manager.theme.id, 'blossom');
    expect(
      (await SharedPreferences.getInstance()).getString('appTheme'),
      'blossom',
    );
    final scheme = manager.lightTheme().colorScheme;
    expect(scheme.primary, const Color(0xFFDB2777));
    expect(scheme.surface, const Color(0xFFFDF7FD));
  });

  test('loads the stored palette and falls back to Graphite', () async {
    SharedPreferences.setMockInitialValues({'appTheme': 'tide'});
    expect((await ThemeManager.loadTheme()).id, 'tide');

    SharedPreferences.setMockInitialValues({'appTheme': 'removed-theme'});
    expect((await ThemeManager.loadTheme()).id, 'graphite');
  });

  test('migrates the old dynamic color switch to Adaptive', () async {
    SharedPreferences.setMockInitialValues({'useDynamicColor': true});
    expect((await ThemeManager.loadTheme()).id, 'adaptive');

    SharedPreferences.setMockInitialValues({'useDynamicColor': false});
    expect((await ThemeManager.loadTheme()).id, 'graphite');
  });

  test('uses wallpaper colors only for Adaptive', () {
    final dynamic = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00A86B),
      brightness: Brightness.light,
    );
    final adaptive = ThemeManager(ThemeMode.light, theme: AppThemes.adaptive);
    final graphite = ThemeManager(ThemeMode.light, theme: AppThemes.graphite);

    expect(
      adaptive.lightTheme(dynamicColorScheme: dynamic).colorScheme.primary,
      dynamic.primary,
    );
    expect(
      graphite.lightTheme(dynamicColorScheme: dynamic).colorScheme.primary,
      const Color(0xFF1B4ED8),
    );
  });

  test('keeps Adaptive readable when wallpaper colors are unavailable', () {
    final scheme = ThemeManager(
      ThemeMode.dark,
      theme: AppThemes.adaptive,
    ).darkTheme().colorScheme;

    expect(scheme.primary, const Color(0xFF9FC6FF));
    expect(scheme.onPrimary, const Color(0xFF002E69));
    expect(scheme.surface, const Color(0xFF101318));
  });

  test('gives every palette a light and dark variant', () {
    for (final theme in AppThemes.all) {
      expect(theme.light.accent, isNot(theme.dark.accent), reason: theme.id);
      expect(
        theme.light.toColorScheme(Brightness.light).brightness,
        Brightness.light,
      );
      expect(
        theme.dark.toColorScheme(Brightness.dark).brightness,
        Brightness.dark,
      );
    }
  });

  test('keeps borders visible on every palette surface', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final lighter = la > lb ? la : lb;
      final darker = la > lb ? lb : la;
      return (lighter + 0.05) / (darker + 0.05);
    }

    for (final theme in AppThemes.all) {
      for (final brightness in Brightness.values) {
        final scheme = theme.palette(brightness).toColorScheme(brightness);
        expect(
          contrast(scheme.outlineVariant, scheme.surface),
          greaterThanOrEqualTo(1.4),
          reason: '${theme.id} ${brightness.name} border on canvas',
        );
        expect(
          contrast(scheme.outlineVariant, scheme.surfaceContainerHigh),
          greaterThanOrEqualTo(1.3),
          reason: '${theme.id} ${brightness.name} border on raised surface',
        );
      }
    }
  });

  test('keeps raised surfaces distinct without adding component outlines', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final lighter = la > lb ? la : lb;
      final darker = la > lb ? lb : la;
      return (lighter + 0.05) / (darker + 0.05);
    }

    for (final theme in AppThemes.all) {
      for (final brightness in Brightness.values) {
        final scheme = theme.palette(brightness).toColorScheme(brightness);
        expect(
          contrast(scheme.surfaceContainerHigh, scheme.surface),
          greaterThanOrEqualTo(brightness == Brightness.light ? 1.05 : 1.2),
          reason: '${theme.id} ${brightness.name} raised surface',
        );
      }
    }

    final data = ThemeManager(ThemeMode.dark).darkTheme();
    expect(data.dividerTheme.color, isNull);
    expect(data.dialogTheme.shape, isNull);
    // Bottom sheets share one rounded shape; it must not draw a border.
    final sheetShape = data.bottomSheetTheme.shape;
    expect(sheetShape, isA<RoundedRectangleBorder>());
    expect((sheetShape! as RoundedRectangleBorder).side, BorderSide.none);
    expect(data.popupMenuTheme.shape, isNull);
    expect(data.cardTheme.shape, isNull);
  });
}
