import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One entry of the bottom navigation bar.
class WobblyNavItem {
  const WobblyNavItem({required this.icon, required this.label, this.selectedIcon});

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
}

/// Bottom navigation bar with a "wobbly" selection indicator.
///
/// Neighbor hops slide with a single soft overshoot ([Curves.easeOutBack])
/// and a springy icon pop; far jumps glide smoothly ([Curves.easeInOutCubic],
/// calm icon settle) so the indicator never oscillates mid-way.
/// Animation duration scales with the jump distance.
/// Apple platforms (iOS/macOS) use a bright liquid-glass look,
/// Android uses an acrylic look (blur + surface tint).
class WobblyNavBar extends StatefulWidget {
  const WobblyNavBar(
      {super.key,
      required this.items,
      required this.selectedIndex,
      required this.onTap});

  final List<WobblyNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  State<WobblyNavBar> createState() => _WobblyNavBarState();
}

class _WobblyNavBarState extends State<WobblyNavBar> {
  late int _previousIndex = widget.selectedIndex;

  @override
  void didUpdateWidget(covariant WobblyNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _previousIndex = oldWidget.selectedIndex;
    }
  }

  /// Slide duration: playful on neighbor tabs, degressive on far jumps
  /// so peak velocity stays roughly constant (300–600 ms).
  Duration get _slideDuration {
    final distance = (widget.selectedIndex - _previousIndex).abs();
    if (distance <= 1) return const Duration(milliseconds: 350);
    return Duration(milliseconds: (280 + distance * 90).clamp(280, 600));
  }

  /// Overshoot only reads well on short travel: elastic neighbor hops,
  /// smooth glide (no oscillation) on far jumps.
  Curve get _slideCurve {
    final distance = (widget.selectedIndex - _previousIndex).abs();
    return distance <= 1 ? Curves.easeOutBack : Curves.easeInOutCubic;
  }

  /// Springy icon pop only for neighbor hops; far jumps settle calmly.
  bool get _springyIcon {
    return (widget.selectedIndex - _previousIndex).abs() <= 1;
  }

  static bool _isApple(BuildContext context) {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isApple = _isApple(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: isApple ? 28 : 18,
          sigmaY: isApple ? 28 : 18,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isApple
                  ? [
                      Colors.white.withValues(alpha: isDark ? 0.22 : 0.55),
                      Colors.white.withValues(alpha: isDark ? 0.08 : 0.22),
                    ]
                  : [
                      cs.surfaceContainer
                          .withValues(alpha: isDark ? 0.72 : 0.82),
                      cs.surfaceContainerLow
                          .withValues(alpha: isDark ? 0.62 : 0.74),
                    ],
            ),
            border: Border.all(
              color: isApple
                  ? Colors.white.withValues(alpha: isDark ? 0.35 : 0.7)
                  : cs.outlineVariant.withValues(alpha: 0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / widget.items.length;
              final rtl =
                  Directionality.of(context) == TextDirection.rtl;
              final position = widget.selectedIndex * itemWidth + 4;
              return Stack(
                children: [
                  // Sliding selection blob: single soft overshoot on
                  // neighbor hops, smooth glide (no oscillation) on far
                  // jumps. Position is RTL-aware.
                  AnimatedPositioned(
                    duration: _slideDuration,
                    curve: _slideCurve,
                    left: rtl ? null : position,
                    right: rtl ? position : null,
                    top: 0,
                    bottom: 0,
                    width: itemWidth - 8,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            cs.primary.withValues(alpha: 0.32),
                            cs.primary.withValues(alpha: 0.16),
                          ],
                        ),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < widget.items.length; i++)
                        Expanded(
                          child: _NavButton(
                            item: widget.items[i],
                            selected: i == widget.selectedIndex,
                            springy: _springyIcon,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              widget.onTap(i);
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton(
      {required this.item,
      required this.selected,
      required this.springy,
      required this.onTap});

  final WobblyNavItem item;
  final bool selected;
  final bool springy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon pop: springy on neighbor hops, calm settle on far jumps
              // (avoids wobbling after arrival).
              TweenAnimationBuilder<double>(
                key: ValueKey<bool>(selected),
                tween:
                    Tween(begin: selected && springy ? 0.6 : 0.85, end: 1),
                duration: Duration(
                    milliseconds: springy ? 600 : 250),
                curve: springy ? Curves.elasticOut : Curves.easeOut,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Icon(
                  selected ? (item.selectedIcon ?? item.icon) : item.icon,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: color,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                child: Text(item.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Platform helper for tests and previews.
@visibleForTesting
bool wobblyNavUsesAppleGlass(TargetPlatform platform) =>
    platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
