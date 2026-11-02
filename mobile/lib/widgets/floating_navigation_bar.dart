import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A destination shown in the [FloatingNavigationBar].
class FloatingNavigationDestination {
  final IconData icon;
  final String label;
  final String? badgeText;
  final bool badgeIsAlert;

  const FloatingNavigationDestination({
    required this.icon,
    required this.label,
    this.badgeText,
    this.badgeIsAlert = false,
  });
}

/// Exposes the extra bottom space that scrollable pages should keep clear
/// while [FloatingNavigationBar] overlays their content.
///
/// The value does not include the device safe-area inset: pages are expected to
/// apply that themselves through [SafeArea].
class FloatingNavigationBarInset extends InheritedWidget {
  final double bottom;

  const FloatingNavigationBarInset({
    super.key,
    required this.bottom,
    required super.child,
  });

  static double of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<FloatingNavigationBarInset>()
            ?.bottom ??
        0;
  }

  @override
  bool updateShouldNotify(FloatingNavigationBarInset oldWidget) {
    return bottom != oldWidget.bottom;
  }
}

/// A compact floating navigation bar modelled on the One UI bar in the
/// official T3 Code mobile app.
///
/// The bar is meant to be placed in an overlay above the page content rather
/// than in [Scaffold.bottomNavigationBar], so lists and other content scroll
/// behind it. It deliberately shows icons only; the labels are exposed to
/// accessibility services and long-press tooltips.
///
/// The bar uses a fixed slot width per destination and stays left-aligned
/// instead of stretching or centring across the whole screen. Its active
/// destination is marked by a compact capsule that slides between slots.
/// Dragging anywhere on the bar moves the capsule with the finger; releasing it
/// selects the nearest destination.
///
/// A [trailing] action can be placed next to the bar. It is rendered at the
/// same height as the bar on the right edge of the screen, with the bar
/// shrinking its slots on narrow screens so both always fit.
class FloatingNavigationBar extends StatefulWidget {
  /// Height of the visible bar surface, matching the T3 Code One UI bar.
  static const double barHeight = 56;
  static const double edgeMargin = 16;
  static const double bottomMargin = 6;

  /// Width of one destination slot. The visible bar is `count * itemExtent`
  /// wide, capped to the available width, and left-aligned.
  static const double itemExtent = 72;
  static const double iconSize = 24;

  /// Diameter of an optional [trailing] action, matching the bar height.
  static const double actionSize = barHeight;

  /// Minimum gap between the bar and a [trailing] action.
  static const double actionGap = 10;

  /// Inset between a slot and the selection capsule, matching T3's 4dp tab
  /// padding. It keeps the capsule visually clear of the bar's rounded ends.
  static const double _selectionPadding = 4;

  /// Extra bottom padding pages should add below their scrollable content when
  /// the bar is floating above them.
  static const double contentInset = barHeight + bottomMargin + edgeMargin;

  /// Key for the sliding selection capsule, useful for tests and screenshots.
  static const Key indicatorKey = ValueKey('floating-navigation-indicator');

  /// Key for the visible bar surface, useful for tests and screenshots.
  static const Key surfaceKey = ValueKey('floating-navigation-surface');

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<FloatingNavigationDestination> destinations;

  /// Optional action shown to the right of the bar at the same height.
  final Widget? trailing;

  const FloatingNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.trailing,
  });

  @override
  State<FloatingNavigationBar> createState() => _FloatingNavigationBarState();
}

class _FloatingNavigationBarState extends State<FloatingNavigationBar>
    with SingleTickerProviderStateMixin {
  static const Duration _indicatorDuration = Duration(milliseconds: 280);

  late final AnimationController _indicator;
  double _barWidth = 0;
  double _dragStartValue = 0;
  double _dragStartX = 0;
  int _lastDragHapticIndex = 0;
  bool _dragging = false;
  bool _reduceMotion = false;

  int get _destinationCount => widget.destinations.length;

  double get _itemWidth {
    return _destinationCount == 0 ? _barWidth : _barWidth / _destinationCount;
  }

  @override
  void initState() {
    super.initState();
    _indicator = AnimationController.unbounded(vsync: this)
      ..value = widget.selectedIndex.toDouble();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion && !_dragging) {
      _indicator.value = widget.selectedIndex.toDouble();
    }
  }

  @override
  void didUpdateWidget(FloatingNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.destinations.length != widget.destinations.length) {
      // The sessions destination can appear or disappear. Snap to the real
      // selection instead of leaving the capsule on a stale index.
      _indicator.value = widget.selectedIndex.toDouble();
      return;
    }

    if (!_dragging && widget.selectedIndex != oldWidget.selectedIndex) {
      _animateIndicatorTo(widget.selectedIndex.toDouble());
    }
  }

  void _animateIndicatorTo(double value) {
    if (_reduceMotion) {
      _indicator.value = value;
      return;
    }
    _indicator.animateTo(
      value,
      duration: _indicatorDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _handleTap(int index) {
    if (index == widget.selectedIndex) return;
    HapticFeedback.selectionClick();
    widget.onDestinationSelected(index);
  }

  void _handleDragStart(DragStartDetails details) {
    _indicator.stop();
    _dragStartValue = _indicator.value;
    _dragStartX = details.localPosition.dx;
    _lastDragHapticIndex = _indicator.value.round();
    setState(() => _dragging = true);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final count = _destinationCount;
    final itemWidth = _itemWidth;
    if (count <= 1 || itemWidth <= 0) return;

    final delta = (details.localPosition.dx - _dragStartX) / itemWidth;
    final value = (_dragStartValue + delta).clamp(0.0, (count - 1).toDouble());
    _indicator.value = value;

    final nearest = value.round();
    if (nearest != _lastDragHapticIndex) {
      _lastDragHapticIndex = nearest;
      HapticFeedback.selectionClick();
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    final count = _destinationCount;
    if (count == 0) return;

    final target = _indicator.value.round().clamp(0, count - 1);
    final changed = target != widget.selectedIndex;
    setState(() => _dragging = false);

    if (!changed) {
      _animateIndicatorTo(widget.selectedIndex.toDouble());
      return;
    }

    widget.onDestinationSelected(target);

    // If the parent rejects the selection (for example because the sessions
    // tab disappeared mid-gesture), settle back on the real destination.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.selectedIndex != target) {
        _animateIndicatorTo(widget.selectedIndex.toDouble());
      }
    });
  }

  void _handleDragCancel() {
    setState(() => _dragging = false);
    _animateIndicatorTo(widget.selectedIndex.toDouble());
  }

  @override
  void dispose() {
    _indicator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _destinationCount;
    if (count == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trailing = widget.trailing;
        final trailingSpace = trailing == null
            ? 0.0
            : FloatingNavigationBar.actionSize +
                  FloatingNavigationBar.actionGap;
        final availableWidth = math.max(
          0.0,
          constraints.maxWidth -
              2 * FloatingNavigationBar.edgeMargin -
              trailingSpace,
        );
        final barWidth = math.min(
          count * FloatingNavigationBar.itemExtent,
          availableWidth,
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(
            FloatingNavigationBar.edgeMargin,
            8,
            FloatingNavigationBar.edgeMargin,
            bottomInset + FloatingNavigationBar.bottomMargin,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                width: barWidth,
                height: FloatingNavigationBar.barHeight,
                child: _buildSurface(
                  context,
                  cs: cs,
                  isDark: isDark,
                  count: count,
                ),
              ),
              if (trailing != null)
                SizedBox(
                  width: FloatingNavigationBar.actionSize,
                  height: FloatingNavigationBar.actionSize,
                  child: trailing,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSurface(
    BuildContext context, {
    required ColorScheme cs,
    required bool isDark,
    required int count,
  }) {
    const radius = BorderRadius.all(
      Radius.circular(FloatingNavigationBar.barHeight / 2),
    );
    final surfaceColor = isDark
        ? cs.surfaceContainerHigh
        : cs.surfaceContainerLow;
    final indicatorColor = Color.alphaBlend(
      cs.primary.withValues(alpha: isDark ? 0.30 : 0.14),
      surfaceColor,
    );
    const selectionPadding = FloatingNavigationBar._selectionPadding;
    const selectionHeight =
        FloatingNavigationBar.barHeight - 2 * selectionPadding;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.46 : 0.20),
            blurRadius: 10,
            spreadRadius: -1,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        key: FloatingNavigationBar.surfaceKey,
        borderRadius: radius,
        child: ColoredBox(
          color: surfaceColor,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _barWidth = constraints.maxWidth;
              final itemWidth = _itemWidth;
              final selectionWidth = math.max(
                0.0,
                itemWidth - 2 * selectionPadding,
              );

              return Semantics(
                container: true,
                label: 'Navigation',
                child: Material(
                  type: MaterialType.transparency,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onHorizontalDragStart: _handleDragStart,
                    onHorizontalDragUpdate: _handleDragUpdate,
                    onHorizontalDragEnd: _handleDragEnd,
                    onHorizontalDragCancel: _handleDragCancel,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedBuilder(
                          animation: _indicator,
                          builder: (context, _) {
                            final value = _indicator.value.clamp(
                              0.0,
                              (count - 1).toDouble(),
                            );
                            return Positioned(
                              left: selectionPadding + value * itemWidth,
                              top: selectionPadding,
                              width: selectionWidth,
                              height: selectionHeight,
                              child: Container(
                                key: FloatingNavigationBar.indicatorKey,
                                decoration: BoxDecoration(
                                  color: indicatorColor,
                                  borderRadius: BorderRadius.circular(
                                    selectionHeight / 2,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < count; i++)
                              Expanded(
                                child: _DestinationButton(
                                  destination: widget.destinations[i],
                                  selected: widget.selectedIndex == i,
                                  surfaceColor: surfaceColor,
                                  selectionColor: indicatorColor,
                                  onTap: () => _handleTap(i),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A compact action button that can be passed as [FloatingNavigationBar.trailing].
///
/// It keeps the look of the previous floating action button: a 56dp rounded
/// square in the theme's accent colour with elevation, only moved down next to
/// the bar.
class FloatingNavigationAction extends StatelessWidget {
  static const double radius = 16;

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Uses the theme's solid error colour so the action still reads as
  /// destructive while sitting beside the accent-coloured primary action.
  final bool destructive;

  const FloatingNavigationAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final background = destructive ? cs.error : cs.primary;
    final foreground = destructive ? cs.onError : cs.onPrimary;

    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        waitDuration: const Duration(milliseconds: 500),
        child: Material(
          color: background,
          elevation: 6,
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            splashColor: foreground.withValues(alpha: 0.10),
            highlightColor: foreground.withValues(alpha: 0.06),
            child: Center(
              child: Icon(
                icon,
                size: FloatingNavigationBar.iconSize,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationButton extends StatelessWidget {
  final FloatingNavigationDestination destination;
  final bool selected;
  final Color surfaceColor;
  final Color selectionColor;
  final VoidCallback onTap;

  const _DestinationButton({
    required this.destination,
    required this.selected,
    required this.surfaceColor,
    required this.selectionColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final badgeText = destination.badgeText;
    final semanticsLabel = badgeText == null
        ? destination.label
        : '${destination.label}, $badgeText';

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: destination.label,
        excludeFromSemantics: true,
        waitDuration: const Duration(milliseconds: 500),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          splashColor: cs.onSurface.withValues(alpha: 0.08),
          highlightColor: cs.onSurface.withValues(alpha: 0.04),
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  destination.icon,
                  size: FloatingNavigationBar.iconSize,
                  color: selected ? cs.primary : cs.onSurface,
                ),
              ),
              if (badgeText != null)
                Positioned(
                  right: 12,
                  top: 6,
                  child: _NavigationBadge(
                    text: badgeText,
                    isAlert: destination.badgeIsAlert,
                    borderColor: selected ? selectionColor : surfaceColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationBadge extends StatelessWidget {
  final String text;
  final bool isAlert;
  final Color borderColor;

  const _NavigationBadge({
    required this.text,
    required this.isAlert,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final background = isAlert ? cs.error : cs.primary;
    final foreground = isAlert ? cs.onError : cs.onPrimary;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.75, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey(text),
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            color: foreground,
            fontSize: 11,
            height: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
