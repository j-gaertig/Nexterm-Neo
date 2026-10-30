import 'dart:ui';

import 'package:flutter/material.dart';

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

/// A translucent, floating navigation bar inspired by Samsung One UI.
///
/// It deliberately shows icons only. The label is exposed to accessibility
/// services and long-press tooltips, so the bar stays compact while remaining
/// discoverable.
class FloatingNavigationBar extends StatelessWidget {
  static const double barHeight = 64;
  static const double _horizontalMargin = 16;
  static const double _bottomMargin = 10;
  static const double _maxWidth = 560;

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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _horizontalMargin,
        8,
        _horizontalMargin,
        bottomInset + _bottomMargin,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(barHeight / 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.36 : 0.13),
                  blurRadius: 28,
                  spreadRadius: -8,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(barHeight / 2),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        cs.surfaceContainerHigh.withValues(
                          alpha: isDark ? 0.80 : 0.88,
                        ),
                        cs.surfaceContainerHigh.withValues(
                          alpha: isDark ? 0.66 : 0.74,
                        ),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(barHeight / 2),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(
                        alpha: isDark ? 0.34 : 0.45,
                      ),
                    ),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Row(
                      children: [
                        for (var i = 0; i < destinations.length; i++)
                          Expanded(
                            child: _DestinationButton(
                              destination: destinations[i],
                              selected: selectedIndex == i,
                              onTap: () => onDestinationSelected(i),
                            ),
                          ),
                      ],
                    ),
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
  final bool selected;
  final VoidCallback onTap;

  const _DestinationButton({
    required this.destination,
    required this.selected,
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
        child: InkResponse(
          onTap: onTap,
          containedInkWell: true,
          customBorder: const CircleBorder(),
          radius: 30,
          child: Center(
            child: SizedBox(
              width: 46,
              height: 46,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? cs.secondaryContainer.withValues(alpha: 0.92)
                      : Colors.transparent,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedScale(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      scale: selected ? 1 : 0.92,
                      child: Icon(
                        destination.icon,
                        size: 23,
                        color: selected
                            ? cs.onSecondaryContainer
                            : cs.onSurfaceVariant,
                      ),
                    ),
                    if (badgeText != null)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: _NavigationBadge(
                          text: badgeText,
                          isAlert: destination.badgeIsAlert,
                        ),
                      ),
                  ],
                ),
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

  const _NavigationBadge({required this.text, required this.isAlert});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final background = isAlert ? cs.error : cs.primary;
    final foreground = isAlert ? cs.onError : cs.onPrimary;

    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.surface.withValues(alpha: 0.9),
          width: 1.5,
        ),
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
    );
  }
}
