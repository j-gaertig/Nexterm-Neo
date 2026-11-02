import 'package:flutter/material.dart';

/// One light or dark palette from Nexterm's built-in color themes.
///
/// Each palette maps a curated set of design tokens onto the Material roles
/// Nexterm uses.
@immutable
class AppThemePalette {
  const AppThemePalette({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.input,
    required this.accent,
    required this.onAccent,
    required this.accentSurface,
    required this.onAccentSurface,
    required this.action,
    required this.onAction,
    required this.actionSurface,
    required this.onActionSurface,
    required this.warning,
    required this.warningForeground,
    required this.warningSurface,
    required this.error,
    required this.errorSurface,
    required this.onErrorSurface,
    required this.codeBackground,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceOverlay;
  final Color text;
  final Color textMuted;
  final Color border;
  final Color input;
  final Color accent;
  final Color onAccent;
  final Color accentSurface;
  final Color onAccentSurface;
  final Color action;
  final Color onAction;
  final Color actionSurface;
  final Color onActionSurface;
  final Color warning;
  final Color warningForeground;
  final Color warningSurface;
  final Color error;
  final Color errorSurface;
  final Color onErrorSurface;
  final Color codeBackground;

  static const Color _onWarning = Color(0xFF241523);
  static const Color _onError = Color(0xFFFFFFFF);

  ColorScheme toColorScheme(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    // Keep the surface hierarchy and border contrast of the Material scheme
    // that shipped before the built-in palettes. Deriving these roles from the
    // palette instead of hard-coding them keeps every theme recognisable while
    // restoring the softer card edges and list separators of the old look.
    Color raised(double alpha) =>
        Color.alphaBlend(text.withValues(alpha: alpha), canvas);
    final outlineVariant = raised(isLight ? 0.22 : 0.27);
    final surfaceLow = raised(isLight ? 0.015 : 0.035);
    final surfaceContainer = raised(isLight ? 0.035 : 0.07);
    final surfaceHigh = raised(isLight ? 0.055 : 0.11);
    final surfaceHighest = raised(isLight ? 0.09 : 0.16);

    return ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: accentSurface,
      onPrimaryContainer: onAccentSurface,
      secondary: action,
      onSecondary: onAction,
      secondaryContainer: actionSurface,
      onSecondaryContainer: onActionSurface,
      tertiary: warning,
      onTertiary: _onWarning,
      tertiaryContainer: warningSurface,
      onTertiaryContainer: warningForeground,
      error: error,
      onError: _onError,
      errorContainer: errorSurface,
      onErrorContainer: onErrorSurface,
      surface: canvas,
      onSurface: text,
      onSurfaceVariant: textMuted,
      // Nexterm uses `outline` for secondary labels as well as borders.
      outline: textMuted,
      outlineVariant: outlineVariant,
      surfaceDim: canvas,
      surfaceBright: surfaceOverlay,
      surfaceContainerLowest: isLight ? surface : canvas,
      surfaceContainerLow: surfaceLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHighest,
      inverseSurface: text,
      onInverseSurface: canvas,
      inversePrimary: accent,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      surfaceTint: accent,
    );
  }
}

/// A paired light/dark palette shown in Appearance settings.
@immutable
class AppThemeDefinition {
  const AppThemeDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.light,
    required this.dark,
    this.usesSystemColor = false,
  });

  final String id;
  final String label;
  final String description;
  final AppThemePalette light;
  final AppThemePalette dark;
  final bool usesSystemColor;

  AppThemePalette palette(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;
}

/// Built-in application themes.
class AppThemes {
  static const AppThemeDefinition graphite = AppThemeDefinition(
    id: 'graphite',
    label: 'Graphite',
    description: 'Crisp neutrals with a blue accent',
    usesSystemColor: false,
    light: _graphiteLight,
    dark: _graphiteDark,
  );

  static const AppThemeDefinition adaptive = AppThemeDefinition(
    id: 'adaptive',
    label: 'Adaptive',
    description: 'Follows your wallpaper on Android 12+',
    usesSystemColor: true,
    light: _adaptiveLight,
    dark: _adaptiveDark,
  );

  static const AppThemeDefinition blossom = AppThemeDefinition(
    id: 'blossom',
    label: 'Blossom',
    description: 'Soft pinks and berry tones',
    usesSystemColor: false,
    light: _blossomLight,
    dark: _blossomDark,
  );

  static const AppThemeDefinition meadow = AppThemeDefinition(
    id: 'meadow',
    label: 'Meadow',
    description: 'Fresh greens with warm gold',
    usesSystemColor: false,
    light: _meadowLight,
    dark: _meadowDark,
  );

  static const AppThemeDefinition tide = AppThemeDefinition(
    id: 'tide',
    label: 'Tide',
    description: 'Cool blues and teal accents',
    usesSystemColor: false,
    light: _tideLight,
    dark: _tideDark,
  );

  static const AppThemeDefinition copper = AppThemeDefinition(
    id: 'copper',
    label: 'Copper',
    description: 'Warm earth tones and burnt orange',
    usesSystemColor: false,
    light: _copperLight,
    dark: _copperDark,
  );

  static const AppThemeDefinition aurora = AppThemeDefinition(
    id: 'aurora',
    label: 'Aurora',
    description: 'Violet tones on deep plum',
    usesSystemColor: false,
    light: _auroraLight,
    dark: _auroraDark,
  );

  static const List<AppThemeDefinition> all = [
    graphite,
    adaptive,
    blossom,
    meadow,
    tide,
    copper,
    aurora,
  ];

  static AppThemeDefinition byId(String? id) =>
      all.firstWhere((theme) => theme.id == id, orElse: () => graphite);

  static const AppThemePalette _graphiteLight = AppThemePalette(
    canvas: Color(0xFFFCFCFC),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFCFCFC),
    surfaceOverlay: Color(0xFFFFFFFF),
    text: Color(0xFF27272A),
    textMuted: Color(0xFF71717B),
    border: Color(0xFFC9C9CF),
    input: Color(0xFFD4D4D8),
    accent: Color(0xFF1B4ED8),
    onAccent: Color(0xFFFFFFFF),
    accentSurface: Color(0xFFF4F4F5),
    onAccentSurface: Color(0xFF18181B),
    action: Color(0xFF1B4ED8),
    onAction: Color(0xFFFFFFFF),
    actionSurface: Color(0xFFF4F4F5),
    onActionSurface: Color(0xFF27272A),
    warning: Color(0xFFFE9A00),
    warningForeground: Color(0xFFBB4D00),
    warningSurface: Color(0xFFFCF4E8),
    error: Color(0xFFFB2C36),
    errorSurface: Color(0xFFFCEBEC),
    onErrorSurface: Color(0xFFC10007),
    codeBackground: Color(0xFFFFFFFF),
  );

  static const AppThemePalette _graphiteDark = AppThemePalette(
    canvas: Color(0xFF0A0A0A),
    surface: Color(0xFF111111),
    surfaceRaised: Color(0xFF111111),
    surfaceOverlay: Color(0xFF111111),
    text: Color(0xFFF5F5F5),
    textMuted: Color(0xFF818181),
    border: Color(0xFF343434),
    input: Color(0xFF1E1E1E),
    accent: Color(0xFF346BF1),
    onAccent: Color(0xFFFFFFFF),
    accentSurface: Color(0xFF141414),
    onAccentSurface: Color(0xFFF5F5F5),
    action: Color(0xFF346BF1),
    onAction: Color(0xFFFFFFFF),
    actionSurface: Color(0xFF141414),
    onActionSurface: Color(0xFFF5F5F5),
    warning: Color(0xFFFE9A00),
    warningForeground: Color(0xFFFFB900),
    warningSurface: Color(0xFF312108),
    error: Color(0xFFFB414A),
    errorSurface: Color(0xFF301214),
    onErrorSurface: Color(0xFFFF6467),
    codeBackground: Color(0xFF111111),
  );

  static const AppThemePalette _adaptiveLight = AppThemePalette(
    canvas: Color(0xFFFAF8FF),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF1F3FB),
    surfaceOverlay: Color(0xFFFFFFFF),
    text: Color(0xFF1A1B21),
    textMuted: Color(0xFF5D5E66),
    border: Color(0xFFC9CBD9),
    input: Color(0xFFD9DAE6),
    accent: Color(0xFF3157D5),
    onAccent: Color(0xFFFFFFFF),
    accentSurface: Color(0xFFE3E7FA),
    onAccentSurface: Color(0xFF141A33),
    action: Color(0xFF00639B),
    onAction: Color(0xFFFFFFFF),
    actionSurface: Color(0xFFD6E9F8),
    onActionSurface: Color(0xFF062033),
    warning: Color(0xFFFE9A00),
    warningForeground: Color(0xFFBB4D00),
    warningSurface: Color(0xFFFCF4E8),
    error: Color(0xFFFB2C36),
    errorSurface: Color(0xFFFCEBEC),
    onErrorSurface: Color(0xFFC10007),
    codeBackground: Color(0xFFF4F5FA),
  );

  static const AppThemePalette _adaptiveDark = AppThemePalette(
    canvas: Color(0xFF101318),
    surface: Color(0xFF171A20),
    surfaceRaised: Color(0xFF1F232B),
    surfaceOverlay: Color(0xFF22262F),
    text: Color(0xFFF5F5F7),
    textMuted: Color(0xFFA9ABB3),
    border: Color(0xFF343945),
    input: Color(0xFF383C45),
    accent: Color(0xFF9FC6FF),
    onAccent: Color(0xFF002E69),
    accentSurface: Color(0xFF1D3A5F),
    onAccentSurface: Color(0xFFD6E3FF),
    action: Color(0xFF7FD0FF),
    onAction: Color(0xFF00344D),
    actionSurface: Color(0xFF203D50),
    onActionSurface: Color(0xFFD6E9F8),
    warning: Color(0xFFFE9A00),
    warningForeground: Color(0xFFFFB900),
    warningSurface: Color(0xFF312108),
    error: Color(0xFFFB414A),
    errorSurface: Color(0xFF301214),
    onErrorSurface: Color(0xFFFF6467),
    codeBackground: Color(0xFF15181E),
  );

  static const AppThemePalette _blossomLight = AppThemePalette(
    canvas: Color(0xFFFDF7FD),
    surface: Color(0xFFFAF3FB),
    surfaceRaised: Color(0xFFFDFAFD),
    surfaceOverlay: Color(0xFFFFFFFF),
    text: Color(0xFF501854),
    textMuted: Color(0xFFAC1668),
    border: Color(0xFFDEC5DC),
    input: Color(0xFFE7C1DC),
    accent: Color(0xFFDB2777),
    onAccent: Color(0xFFFFFFFF),
    accentSurface: Color(0xFFF3E6F5),
    onAccentSurface: Color(0xFF454554),
    action: Color(0xFFDB2777),
    onAction: Color(0xFFFFFFFF),
    actionSurface: Color(0xFFF7DEF2),
    onActionSurface: Color(0xFF492C61),
    warning: Color(0xFFF59E0B),
    warningForeground: Color(0xFFB05109),
    warningSurface: Color(0xFFFCF0EA),
    error: Color(0xFFF7086C),
    errorSurface: Color(0xFFFDE4F1),
    onErrorSurface: Color(0xFF9D174D),
    codeBackground: Color(0xFFF5ECF9),
  );

  static const AppThemePalette _blossomDark = AppThemePalette(
    canvas: Color(0xFF1F1A24),
    surface: Color(0xFF29232D),
    surfaceRaised: Color(0xFF2C2631),
    surfaceOverlay: Color(0xFF100A0E),
    text: Color(0xFFF9F8FB),
    textMuted: Color(0xFFE7D0DD),
    border: Color(0xFF443A49),
    input: Color(0xFF302029),
    accent: Color(0xFFA3004C),
    onAccent: Color(0xFFFBD0E8),
    accentSurface: Color(0xFF463753),
    onAccentSurface: Color(0xFFF8F1F5),
    action: Color(0xFFA3004C),
    onAction: Color(0xFFFBD0E8),
    actionSurface: Color(0xFF2B2431),
    onActionSurface: Color(0xFFF2EBFA),
    warning: Color(0xFFF59E0B),
    warningForeground: Color(0xFFFBBF24),
    warningSurface: Color(0xFF412F20),
    error: Color(0xFF9D174D),
    errorSurface: Color(0xFF331A2B),
    onErrorSurface: Color(0xFFFBD0E8),
    codeBackground: Color(0xFF1F1A24),
  );

  static const AppThemePalette _meadowLight = AppThemePalette(
    canvas: Color(0xFFF3F7F4),
    surface: Color(0xFFF3F7F4),
    surfaceRaised: Color(0xFFECEFED),
    surfaceOverlay: Color(0xFFE7E9E8),
    text: Color(0xFF241523),
    textMuted: Color(0xFF746C73),
    border: Color(0xFFB6C6BE),
    input: Color(0xFFBECBC5),
    accent: Color(0xFF1B7D50),
    onAccent: Color(0xFFFFFAFF),
    accentSurface: Color(0xFFD5E6DD),
    onAccentSurface: Color(0xFF241523),
    action: Color(0xFF8F6410),
    onAction: Color(0xFFFFFAFF),
    actionSurface: Color(0xFFCCE1D7),
    onActionSurface: Color(0xFF241523),
    warning: Color(0xFFFE9A00),
    warningForeground: Color(0xFFB64A00),
    warningSurface: Color(0xFFF4F0E1),
    error: Color(0xFFFB2C36),
    errorSurface: Color(0xFFF4E7E5),
    onErrorSurface: Color(0xFFC10007),
    codeBackground: Color(0xFFEEF1EF),
  );

  static const AppThemePalette _meadowDark = AppThemePalette(
    canvas: Color(0xFF1B2821),
    surface: Color(0xFF1B2821),
    surfaceRaised: Color(0xFF36413C),
    surfaceOverlay: Color(0xFF444D49),
    text: Color(0xFFFFFAFF),
    textMuted: Color(0xFF919595),
    border: Color(0xFF415F4F),
    input: Color(0xFF4F725F),
    accent: Color(0xFF69D69A),
    onAccent: Color(0xFF241523),
    accentSurface: Color(0xFF325C46),
    onAccentSurface: Color(0xFFFFFAFF),
    action: Color(0xFFE3B34E),
    onAction: Color(0xFF241523),
    actionSurface: Color(0xFF37664D),
    onActionSurface: Color(0xFFFFFAFF),
    warning: Color(0xFFFE9A00),
    warningForeground: Color(0xFFFFB900),
    warningSurface: Color(0xFF3F3A1C),
    error: Color(0xFFFB414A),
    errorSurface: Color(0xFF3F2C28),
    onErrorSurface: Color(0xFFFF6668),
    codeBackground: Color(0xFF28342E),
  );

  static const AppThemePalette _tideLight = AppThemePalette(
    canvas: Color(0xFFF5F7F8),
    surface: Color(0xFFF5F7F8),
    surfaceRaised: Color(0xFFEDEFF1),
    surfaceOverlay: Color(0xFFE8E9EB),
    text: Color(0xFF241523),
    textMuted: Color(0xFF746C75),
    border: Color(0xFFBCC7D1),
    input: Color(0xFFC0C9D4),
    accent: Color(0xFF2672AF),
    onAccent: Color(0xFFFFFAFF),
    accentSurface: Color(0xFFD8E4EE),
    onAccentSurface: Color(0xFF241523),
    action: Color(0xFF0A6F75),
    onAction: Color(0xFFFFFAFF),
    actionSurface: Color(0xFFD0DFEB),
    onActionSurface: Color(0xFF241523),
    warning: Color(0xFFFE9A00),
    warningForeground: Color(0xFFB74B00),
    warningSurface: Color(0xFFF6EFE4),
    error: Color(0xFFFB2C36),
    errorSurface: Color(0xFFF5E6E9),
    onErrorSurface: Color(0xFFC10007),
    codeBackground: Color(0xFFF0F1F3),
  );

  static const AppThemePalette _tideDark = AppThemePalette(
    canvas: Color(0xFF17212B),
    surface: Color(0xFF17212B),
    surfaceRaised: Color(0xFF333B45),
    surfaceOverlay: Color(0xFF414851),
    text: Color(0xFFFFFAFF),
    textMuted: Color(0xFF8D8F97),
    border: Color(0xFF405567),
    input: Color(0xFF4F677B),
    accent: Color(0xFF70B9EE),
    onAccent: Color(0xFF241523),
    accentSurface: Color(0xFF324E66),
    onAccentSurface: Color(0xFFFFFAFF),
    action: Color(0xFF5BD0D6),
    onAction: Color(0xFF241523),
    actionSurface: Color(0xFF375871),
    onActionSurface: Color(0xFFFFFAFF),
    warning: Color(0xFFFE9A00),
    warningForeground: Color(0xFFFFB900),
    warningSurface: Color(0xFF3C3424),
    error: Color(0xFFFB414A),
    errorSurface: Color(0xFF3C2630),
    onErrorSurface: Color(0xFFFF6467),
    codeBackground: Color(0xFF252E38),
  );

  static const AppThemePalette _copperLight = AppThemePalette(
    canvas: Color(0xFFF9F7F5),
    surface: Color(0xFFF9F7F5),
    surfaceRaised: Color(0xFFF1EFEE),
    surfaceOverlay: Color(0xFFECE9E9),
    text: Color(0xFF241523),
    textMuted: Color(0xFF766C74),
    border: Color(0xFFCDBEB8),
    input: Color(0xFFD4C6C1),
    accent: Color(0xFFAE552A),
    onAccent: Color(0xFFFFFAFF),
    accentSurface: Color(0xFFEEE0D9),
    onAccentSurface: Color(0xFF241523),
    action: Color(0xFFB23535),
    onAction: Color(0xFFFFFAFF),
    actionSurface: Color(0xFFEBDAD1),
    onActionSurface: Color(0xFF241523),
    warning: Color(0xFFFE9A00),
    warningForeground: Color(0xFFB84B00),
    warningSurface: Color(0xFFF9EFE2),
    error: Color(0xFFFB2C36),
    errorSurface: Color(0xFFF9E7E6),
    onErrorSurface: Color(0xFFC10007),
    codeBackground: Color(0xFFF3F1F0),
  );

  static const AppThemePalette _copperDark = AppThemePalette(
    canvas: Color(0xFF291E1A),
    surface: Color(0xFF291E1A),
    surfaceRaised: Color(0xFF433835),
    surfaceOverlay: Color(0xFF4F4543),
    text: Color(0xFFFFFAFF),
    textMuted: Color(0xFF968E8F),
    border: Color(0xFF664C3F),
    input: Color(0xFF7A5D4D),
    accent: Color(0xFFF09A64),
    onAccent: Color(0xFF241523),
    accentSurface: Color(0xFF644330),
    onAccentSurface: Color(0xFFFFFAFF),
    action: Color(0xFFF78A7A),
    onAction: Color(0xFF241523),
    actionSurface: Color(0xFF704B34),
    onActionSurface: Color(0xFFFFFAFF),
    warning: Color(0xFFFE9A00),
    warningForeground: Color(0xFFFFB900),
    warningSurface: Color(0xFF4B3215),
    error: Color(0xFFFB414A),
    errorSurface: Color(0xFF4A2321),
    onErrorSurface: Color(0xFFFF6467),
    codeBackground: Color(0xFF362B27),
  );

  static const AppThemePalette _auroraLight = AppThemePalette(
    canvas: Color(0xFFF8F7F9),
    surface: Color(0xFFF8F7F9),
    surfaceRaised: Color(0xFFF0EFF2),
    surfaceOverlay: Color(0xFFEBE9ED),
    text: Color(0xFF241523),
    textMuted: Color(0xFF766C76),
    border: Color(0xFFC8C1D2),
    input: Color(0xFFCCC5D6),
    accent: Color(0xFF7253B9),
    onAccent: Color(0xFFFFFAFF),
    accentSurface: Color(0xFFE5E0F0),
    onAccentSurface: Color(0xFF241523),
    action: Color(0xFFA82C87),
    onAction: Color(0xFFFFFAFF),
    actionSurface: Color(0xFFE0D9EE),
    onActionSurface: Color(0xFF241523),
    warning: Color(0xFFFE9A00),
    warningForeground: Color(0xFFB84B00),
    warningSurface: Color(0xFFF8EFE5),
    error: Color(0xFFFB2C36),
    errorSurface: Color(0xFFF8E6EA),
    onErrorSurface: Color(0xFFC10007),
    codeBackground: Color(0xFFF2F1F4),
  );

  static const AppThemePalette _auroraDark = AppThemePalette(
    canvas: Color(0xFF1D1929),
    surface: Color(0xFF1D1929),
    surfaceRaised: Color(0xFF383443),
    surfaceOverlay: Color(0xFF454250),
    text: Color(0xFFFFFAFF),
    textMuted: Color(0xFF8E8A95),
    border: Color(0xFF4D4366),
    input: Color(0xFF5D527B),
    accent: Color(0xFF9D7DF2),
    onAccent: Color(0xFF241523),
    accentSurface: Color(0xFF433765),
    onAccentSurface: Color(0xFFFFFAFF),
    action: Color(0xFFF099D8),
    onAction: Color(0xFF241523),
    actionSurface: Color(0xFF4B3D72),
    onActionSurface: Color(0xFFFFFAFF),
    warning: Color(0xFFFE9A00),
    warningForeground: Color(0xFFFFB900),
    warningSurface: Color(0xFF412E23),
    error: Color(0xFFFB414A),
    errorSurface: Color(0xFF40202E),
    onErrorSurface: Color(0xFFFF6467),
    codeBackground: Color(0xFF2A2736),
  );
}
