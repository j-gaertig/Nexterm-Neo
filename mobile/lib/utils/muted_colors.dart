import 'package:flutter/material.dart';

/// Background for a server tile that should recede, such as a disabled or
/// offline entry.
///
/// Some palettes use saturated container roles for their highest surface,
/// which can make an inactive tile louder than an active one. Blending the
/// foreground over the surface keeps the inactive state quiet in every theme.
Color mutedTileBackground(ColorScheme scheme) =>
    scheme.onSurface.withValues(alpha: 0.07);

/// Icon colour for a disabled or offline server tile.
Color mutedTileForeground(ColorScheme scheme) =>
    scheme.onSurface.withValues(alpha: 0.42);

/// Title and subtitle colour for a disabled or offline server row.
Color mutedServerText(ColorScheme scheme) =>
    scheme.onSurface.withValues(alpha: 0.55);
