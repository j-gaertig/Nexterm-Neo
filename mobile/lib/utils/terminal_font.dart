/// Bundled Nerd Font used by every mobile terminal surface.
///
/// The font is a patched JetBrains Mono Mono variant, so its cell advance is
/// identical to the regular family while Powerline/Material/Nerd glyphs are
/// available without a network request. Keep this value in sync with the
/// `fonts:` declaration in pubspec.yaml.
const String terminalNerdFontFamily = 'JetBrainsMono Nerd Font Mono';

const List<String> terminalNerdFontFallback = <String>[
  'JetBrains Mono',
  'Roboto Mono',
  'Noto Sans Mono',
  'monospace',
];
