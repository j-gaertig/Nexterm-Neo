import 'package:flutter/material.dart';

import '../services/session_manager.dart';
import '../utils/app_icons.dart';
import 'floating_navigation_bar.dart';

/// App-wide state of the floating main navigation.
///
/// The top-level pages live in [MainNavigationPage], but settings sub-pages and
/// other full-screen routes are pushed above it. Keeping the selected
/// destination here lets those routes show the same navigation bar and jump
/// back to a top-level destination when one of its slots is tapped.
class MainNavigationController extends ChangeNotifier {
  int _selectedIndex = 0;

  int get selectedIndex => _selectedIndex;

  /// Selects a top-level destination and notifies every navigation bar that is
  /// currently visible.
  void select(int index) {
    if (index == _selectedIndex) return;
    _selectedIndex = index;
    notifyListeners();
  }
}

/// Exposes the main navigation controller and session state above the
/// [Navigator], so every pushed route can render the floating bar.
class MainNavigationScope extends InheritedWidget {
  final MainNavigationController controller;
  final SessionManager sessionManager;

  /// False while the app is not signed in. In that state there are no
  /// top-level destinations, so full-screen setup pages keep their own back
  /// affordance instead of showing the bar.
  final bool enabled;

  const MainNavigationScope({
    super.key,
    required this.controller,
    required this.sessionManager,
    required this.enabled,
    required super.child,
  });

  static MainNavigationScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MainNavigationScope>();
  }

  @override
  bool updateShouldNotify(MainNavigationScope oldWidget) {
    return controller != oldWidget.controller ||
        sessionManager != oldWidget.sessionManager ||
        enabled != oldWidget.enabled;
  }
}

/// Builds the destinations shown in the main floating navigation bar.
///
/// The sessions destination only exists while a session is open, exactly like
/// the bar on [MainNavigationPage].
List<FloatingNavigationDestination> mainNavigationDestinations(
  SessionManager sessionManager,
) {
  final sessionCount = sessionManager.sessionCount;
  final waitingCount = sessionManager.waitingInputCount;

  return [
    const FloatingNavigationDestination(icon: AppIcons.dns, label: 'Servers'),
    if (sessionManager.hasActiveSessions)
      FloatingNavigationDestination(
        icon: AppIcons.monitorMultiple,
        label: waitingCount > 0 ? 'Sessions · input' : 'Sessions',
        badgeText: waitingCount > 0 ? '!' : '$sessionCount',
        badgeIsAlert: waitingCount > 0,
      ),
    const FloatingNavigationDestination(
      icon: AppIcons.chartBoxOutline,
      label: 'Monitoring',
    ),
    const FloatingNavigationDestination(icon: AppIcons.cog, label: 'Settings'),
  ];
}
