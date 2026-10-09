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
/// The indicator slides to the active button with a single soft overshoot
/// ([Curves.easeOutBack]) and the icon pops with a spring animation.
/// Animation duration scales with the jump distance so far jumps stay
/// smooth instead of oscillating back and forth.
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

  /// Slide duration grows with jump distance (350–700 ms).
  Duration get _slideDuration {
    final distance = (widget.selectedIndex - _previousIndex).abs();
    return Duration(milliseconds: (350 + distance * 110).clamp(350, 700));
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
              return Stack(
                children: [
                  // Sliding selection blob: single soft overshoot, no
                  // back-and-forth oscillation on far jumps.
                  AnimatedPositioned(
                    duration: _slideDuration,
                    curve: Curves.easeOutBack,
                    left: widget.selectedIndex * itemWidth + 4,
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
      {required this.item, required this.selected, required this.onTap});

  final WobblyNavItem item;
  final bool selected;
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
              // Icon with spring pop on selection (short travel, keeps the
            // playful elastic feel without oscillation).
              TweenAnimationBuilder<double>(
                key: ValueKey<bool>(selected),
                tween: Tween(begin: selected ? 0.6 : 1, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
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
