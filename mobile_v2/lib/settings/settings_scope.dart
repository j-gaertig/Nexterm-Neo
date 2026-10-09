import 'package:flutter/widgets.dart';

import 'app_settings.dart';

/// Provides [AppSettings] down the widget tree (HomeShell → viewers).
///
/// Viewers read prefs with [SettingsScope.of] and fall back to device
/// defaults when no scope exists (e.g. widget tests that build screens
/// directly).
class SettingsScope extends InheritedWidget {
  const SettingsScope(
      {super.key, required this.settings, required super.child});

  final AppSettings settings;

  static AppSettings? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SettingsScope>()
      ?.settings;

  // AppSettings is a mutable ChangeNotifier whose identity never changes
  // (HomeShell holds one instance), so always notify — otherwise viewers
  // would keep stale prefs until the next navigation.
  @override
  bool updateShouldNotify(SettingsScope oldWidget) => true;
}
