import 'dart:math' as math;
import 'dart:ui';

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

/// A translucent, floating navigation bar inspired by Samsung One UI.
///
/// The bar is meant to be placed in an overlay above the page content rather
/// than in [Scaffold.bottomNavigationBar], so lists and other content scroll
/// behind it. It deliberately shows icons only; the labels are exposed to
/// accessibility services and long-press tooltips.
///
/// The active destination is marked by a compact capsule that slides between
/// destinations. Dragging anywhere on the bar moves the capsule with the
/// finger; releasing it selects the nearest destination.
class FloatingNavigationBar extends StatefulWidget {
  static const double barHeight = 64;
  static const double horizontalMargin = 16;
  static const double bottomMargin = 10;
  static const double maxWidth = 560;

  /// Extra bottom padding pages should add below their scrollable content when
  /// the bar is floating above them.
  static const double contentInset = barHeight + bottomMargin + 8;

  /// Key for the sliding selection capsule, useful for tests and screenshots.
  static const Key indicatorKey = ValueKey('floating-navigation-indicator');

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<FloatingNavigationDestination> destinations;

  const FloatingNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  State<FloatingNavigationBar> createState() => _FloatingNavigationBarState();
}

class _FloatingNavigationBarState extends State<FloatingNavigationBar>
    with SingleTickerProviderStateMixin {
  static const Duration _indicatorDuration = Duration(milliseconds: 280);
  static const Duration _dragScaleDuration = Duration(milliseconds: 140);

  late final AnimationController _indicator;
  double _barWidth = 0;
  double _dragStartValue = 0;
  double _dragStartX = 0;
  int _lastDragHapticIndex = 0;
  bool _dragging = false;
  bool _reduceMotion = false;

  int get _destinationCount => widget.destinations.length;

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
    if (count <= 1 || _barWidth <= 0) return;

    final itemWidth = _barWidth / count;
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final count = _destinationCount;
    final maxIndex = math.max(0, count - 1);
    final selected = widget.selectedIndex.clamp(0, maxIndex);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        FloatingNavigationBar.horizontalMargin,
        8,
        FloatingNavigationBar.horizontalMargin,
        bottomInset + FloatingNavigationBar.bottomMargin,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: FloatingNavigationBar.maxWidth,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                FloatingNavigationBar.barHeight / 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.15),
                  blurRadius: 30,
                  spreadRadius: -10,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: cs.primary.withValues(alpha: isDark ? 0.10 : 0.06),
                  blurRadius: 24,
                  spreadRadius: -8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                FloatingNavigationBar.barHeight / 2,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  height: FloatingNavigationBar.barHeight,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.surfaceContainerHigh.withValues(
                          alpha: isDark ? 0.86 : 0.92,
                        ),
                        cs.surfaceContainer.withValues(
                          alpha: isDark ? 0.72 : 0.82,
                        ),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(
                      FloatingNavigationBar.barHeight / 2,
                    ),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(
                        alpha: isDark ? 0.28 : 0.42,
                      ),
                      width: 0.8,
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _barWidth = constraints.maxWidth;
                      final itemWidth = count == 0
                          ? constraints.maxWidth
                          : constraints.maxWidth / count;
                      final pillWidth = math.min(
                        64.0,
                        math.max(0.0, itemWidth - 12),
                      );
                      const pillHeight = 40.0;
                      final pillLeftBase = (itemWidth - pillWidth) / 2;
                      final pillTop =
                          (FloatingNavigationBar.barHeight - pillHeight) / 2;

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
                                      maxIndex.toDouble(),
                                    );
                                    return Positioned(
                                      left: pillLeftBase + value * itemWidth,
                                      top: pillTop,
                                      width: pillWidth,
                                      height: pillHeight,
                                      child: AnimatedScale(
                                        scale: _dragging ? 1.06 : 1.0,
                                        duration: _dragScaleDuration,
                                        curve: Curves.easeOutCubic,
                                        child: Container(
                                          key: FloatingNavigationBar
                                              .indicatorKey,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                cs.primaryContainer.withValues(
                                                  alpha: 0.98,
                                                ),
                                                cs.secondaryContainer
                                                    .withValues(alpha: 0.94),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              pillHeight / 2,
                                            ),
                                            border: Border.all(
                                              color: cs.primary.withValues(
                                                alpha: isDark ? 0.24 : 0.16,
                                              ),
                                              width: 0.8,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: cs.primary.withValues(
                                                  alpha: isDark ? 0.30 : 0.16,
                                                ),
                                                blurRadius: 18,
                                                spreadRadius: -4,
                                                offset: const Offset(0, 6),
                                              ),
                                            ],
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
                                          index: i,
                                          selected: selected == i,
                                          indicator: _indicator,
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
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationButton extends StatelessWidget {
  final FloatingNavigationDestination destination;
  final int index;
  final bool selected;
  final Animation<double> indicator;
  final VoidCallback onTap;

  const _DestinationButton({
    required this.destination,
    required this.index,
    required this.selected,
    required this.indicator,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          borderRadius: BorderRadius.circular(20),
          splashColor: cs.primary.withValues(alpha: 0.12),
          highlightColor: cs.primary.withValues(alpha: 0.06),
          child: Center(
            child: SizedBox(
              width: 64,
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: indicator,
                    builder: (context, _) {
                      final distance = (indicator.value - index).abs().clamp(
                        0.0,
                        1.0,
                      );
                      final progress = 1.0 - distance;
                      return Transform.scale(
                        scale: 0.92 + 0.08 * progress,
                        child: Icon(
                          destination.icon,
                          size: 23,
                          color: Color.lerp(
                            cs.onSurfaceVariant,
                            cs.onPrimaryContainer,
                            progress,
                          ),
                        ),
                      );
                    },
                  ),
                  if (badgeText != null)
                    Positioned(
                      right: 4,
                      top: -2,
                      child: _NavigationBadge(
                        text: badgeText,
                        isAlert: destination.badgeIsAlert,
                        borderColor: cs.surfaceContainerHigh.withValues(
                          alpha: isDark ? 0.92 : 0.96,
                        ),
                      ),
                    ),
                ],
              ),
            ),
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
        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            color: foreground,
            fontSize: 9.5,
            height: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
