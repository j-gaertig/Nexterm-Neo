import 'package:flutter/material.dart';

/// Pushes [builder] as a normal page.
///
/// Inside a top-level tab this resolves to the tab's own navigator, so the
/// floating navigation bar stays visible and the page survives tab switches.
/// Pass [showNavBar] = false for full-screen flows (sign-in, camera) that
/// should cover the bar.
Future<T?> pushPage<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool showNavBar = true,
}) {
  return Navigator.of(
    context,
    rootNavigator: !showNavBar,
  ).push<T>(MaterialPageRoute<T>(builder: builder));
}

/// Hosts a tab's page in its own [Navigator].
///
/// Keeping one navigator per tab means pages pushed on a tab (instance list,
/// server editor, ...) stay open when the user visits another tab and come
/// back to the same place. [navigatorKey] lets the shell pop one step when
/// the active tab's icon is tapped again.
class TabNavigator extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final WidgetBuilder builder;

  const TabNavigator({
    super.key,
    required this.navigatorKey,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (settings) =>
          MaterialPageRoute<void>(settings: settings, builder: builder),
    );
  }
}
