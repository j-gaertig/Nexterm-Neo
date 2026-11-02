import 'package:flutter/material.dart';

import '../../utils/app_themes.dart';

/// A miniature server list rendered from a theme's real surface tokens.
///
/// The same design is used by the appearance row in settings and by the theme
/// gallery, so a palette looks identical in both places. The preview is drawn
/// at a fixed design size and scaled to fit, which keeps every element in
/// proportion no matter how small the thumbnail gets.
class ThemeMiniPreview extends StatelessWidget {
  static const Size designSize = Size(160, 121);

  final AppThemeDefinition theme;
  final Brightness brightness;

  const ThemeMiniPreview({
    super.key,
    required this.theme,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = theme.palette(brightness).toColorScheme(brightness);
    final muted = scheme.onSurfaceVariant;

    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox.fromSize(
        size: designSize,
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 5),
                  _MiniBar(
                    color: scheme.onSurface.withValues(alpha: 0.9),
                    width: 34,
                    height: 4.5,
                  ),
                  const Spacer(),
                  Container(
                    width: 26,
                    height: 9,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                height: 14,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    _MiniBar(
                      color: muted.withValues(alpha: 0.7),
                      width: 42,
                      height: 3,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              _MiniServerRow(scheme: scheme, primaryTile: true),
              const SizedBox(height: 4),
              _MiniServerRow(scheme: scheme, primaryTile: false),
              const SizedBox(height: 5),
              Container(
                height: 13,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(6.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 7,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(3.5),
                      ),
                    ),
                    const Spacer(),
                    _MiniDot(color: muted),
                    const Spacer(),
                    _MiniDot(color: muted),
                    const Spacer(),
                    _MiniDot(color: muted),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniServerRow extends StatelessWidget {
  final ColorScheme scheme;
  final bool primaryTile;

  const _MiniServerRow({required this.scheme, required this.primaryTile});

  @override
  Widget build(BuildContext context) {
    final tile = primaryTile ? scheme.primary : scheme.primaryContainer;
    final onTile = primaryTile ? scheme.onPrimary : scheme.onPrimaryContainer;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: tile,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Container(
                width: 6,
                height: 2,
                decoration: BoxDecoration(
                  color: onTile,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MiniBar(
                  color: scheme.onSurface.withValues(alpha: 0.9),
                  width: 34,
                  height: 3.5,
                ),
                const SizedBox(height: 2.5),
                _MiniBar(
                  color: scheme.onSurfaceVariant,
                  width: 22,
                  height: 2.5,
                ),
              ],
            ),
          ),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  final Color color;
  final double width;
  final double height;

  const _MiniBar({
    required this.color,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}

class _MiniDot extends StatelessWidget {
  final Color color;

  const _MiniDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
