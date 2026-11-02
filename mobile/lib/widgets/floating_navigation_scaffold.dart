import 'package:flutter/material.dart';

import '../utils/app_icons.dart';
import 'floating_navigation_bar.dart';
import 'main_navigation_scope.dart';

/// Wraps a full-screen page with the app's floating navigation bar.
///
/// Settings sub-pages and other routes are pushed above [MainNavigationPage],
/// so they would otherwise cover the bar. This scaffold keeps the bar visible
/// and moves the page's own action next to it, replacing the usual top-left
/// back button. By default that action goes back; pages can supply their own
/// action through [trailing] instead.
///
/// The [builder] runs below [FloatingNavigationBarInset], so pages can keep
/// their scrollable content clear of the bar:
///
/// ```dart
/// FloatingNavigationScaffold(
///   builder: (context) => ListView(
///     padding: EdgeInsets.only(
///       bottom: 24 + FloatingNavigationBarInset.of(context),
///     ),
///     ...
///   ),
/// )
/// ```
class FloatingNavigationScaffold extends StatelessWidget {
  /// Builds the page content. Runs below the inset inherited widget.
  final WidgetBuilder builder;

  /// Overrides the default pop action of the back button.
  final VoidCallback? onBack;

  /// Accessibility label and tooltip of the back button.
  final String backTooltip;

  /// Whether a back action should be shown when the route can be popped.
  final bool showBackAction;

  /// Page-specific action shown next to the bar instead of the back action.
  ///
  /// Use this for pages that have an action of their own, such as adding a
  /// server connection. Their back navigation is handled by the bar itself:
  /// tapping a destination returns to the top-level page.
  final Widget? trailing;

  const FloatingNavigationScaffold({
    super.key,
    required this.builder,
    this.onBack,
    this.backTooltip = 'Back',
    this.showBackAction = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scope = MainNavigationScope.maybeOf(context);
    final showBar =
        scope != null &&
        scope.enabled &&
        MediaQuery.viewInsetsOf(context).bottom == 0;
    final navInset = showBar ? FloatingNavigationBar.contentInset : 0.0;

    final theme = Theme.of(context);
    final pageTheme = showBar
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
        : theme;

    final action = showBar
        ? trailing ??
              (showBackAction && Navigator.of(context).canPop()
                  ? FloatingNavigationAction(
                      icon: AppIcons.arrowBack,
                      tooltip: backTooltip,
                      onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                    )
                  : null)
        : null;

    return Theme(
      data: pageTheme,
      child: Scaffold(
        // The wrapped page builds its own Scaffold. Letting this outer one
        // resize for the keyboard too would apply the inset twice.
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            FloatingNavigationBarInset(
              bottom: navInset,
              child: Builder(builder: builder),
            ),
            if (scope != null && showBar)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    scope.controller,
                    scope.sessionManager,
                  ]),
                  builder: (context, _) {
                    final destinations = mainNavigationDestinations(
                      scope.sessionManager,
                    );
                    final selectedIndex = scope.controller.selectedIndex.clamp(
                      0,
                      destinations.length - 1,
                    );

                    return FloatingNavigationBar(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: (index) {
                        // The bar belongs to the top-level shell. Return to it
                        // before switching destinations so the selected page
                        // is the one the user just tapped.
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                        scope.controller.select(index);
                      },
                      onDestinationReselected: () {
                        // Tapping the destination that is already selected
                        // closes the sub-page instead of doing nothing.
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                      },
                      trailing: action,
                      destinations: destinations,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
