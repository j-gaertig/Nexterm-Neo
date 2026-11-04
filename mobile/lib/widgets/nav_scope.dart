import 'package:flutter/material.dart';

import 'floating_navigation_bar.dart';

/// Gives pushed sub pages access to the main navigation bar.
///
/// [MainNavigationPage] provides it. Pages that are pushed on top of a tab
/// (settings sub pages, the server editor, ...) are shown through [pushPage],
/// which re-attaches the same floating bar, so the bar stays visible on every
/// screen that is not a connection or session.
class MainNavScope extends InheritedWidget {
  final MainNavController controller;

  const MainNavScope({
    super.key,
    required this.controller,
    required super.child,
  });

  static MainNavController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MainNavScope>()?.controller;

  @override
  bool updateShouldNotify(MainNavScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Live navigation state shared with pushed pages. Pushed routes live outside
/// the main page's widget subtree, so they listen to this object instead of
/// an inherited widget.
class MainNavController extends ChangeNotifier {
  int selectedIndex = 0;
  List<FloatingNavigationDestination> destinations = const [];

  /// Switches to a tab after the pushed pages have been closed.
  ValueChanged<int> onSelect = (_) {};

  bool _notifyScheduled = false;

  /// Called from the main page's build. Notifies listeners after the frame so
  /// pushed pages never rebuild while the main page is still building.
  void update({
    required int selectedIndex,
    required List<FloatingNavigationDestination> destinations,
    required ValueChanged<int> onSelect,
  }) {
    final changed =
        this.selectedIndex != selectedIndex ||
        this.destinations.length != destinations.length;
    this.selectedIndex = selectedIndex;
    this.destinations = destinations;
    this.onSelect = onSelect;
    if (!changed || _notifyScheduled) return;
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}

/// Pushes [builder] as a normal page, keeping the floating navigation bar.
///
/// Falls back to a plain route when no [MainNavScope] is available (for
/// example before sign-in).
Future<T?> pushPage<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool showNavBar = true,
}) {
  final controller = showNavBar ? MainNavScope.maybeOf(context) : null;
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      builder: (routeContext) {
        final page = builder(routeContext);
        if (controller == null) return page;
        return _NavBarPage(controller: controller, child: page);
      },
    ),
  );
}

class _NavBarPage extends StatelessWidget {
  final MainNavController controller;
  final Widget child;

  const _NavBarPage({required this.controller, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final showBar = !keyboardOpen;

    return Theme(
      data: showBar
          ? theme.copyWith(
              snackBarTheme: theme.snackBarTheme.copyWith(
                behavior: SnackBarBehavior.floating,
                insetPadding: const EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  FloatingNavigationBar.contentInset + 8,
                ),
              ),
            )
          : theme,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FloatingNavigationBarInset(
            bottom: showBar ? FloatingNavigationBar.contentInset : 0,
            child: child,
          ),
          if (showBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => FloatingNavigationBar(
                  selectedIndex: controller.selectedIndex,
                  destinations: controller.destinations,
                  onDestinationSelected: (index) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    controller.onSelect(index);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
