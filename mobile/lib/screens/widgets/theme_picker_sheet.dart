import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/app_ui.dart';
import '../../utils/app_icons.dart';
import '../../utils/app_themes.dart';
import '../../utils/theme_manager.dart';
import 'theme_mini_preview.dart';

/// Opens the palette gallery. The sheet re-themes itself as soon as a palette
/// is selected, so the choice can be judged in place before closing it.
Future<void> showThemePickerSheet(
  BuildContext context,
  ThemeManager themeManager,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => ThemePickerSheet(themeManager: themeManager),
  );
}

class ThemePickerSheet extends StatelessWidget {
  final ThemeManager themeManager;

  const ThemePickerSheet({super.key, required this.themeManager});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final textScale = media.textScaler.scale(1).clamp(1.0, 2.0);
    final tileHeight = 140 + (textScale - 1) * 34;
    final columns = media.size.width >= 600 ? 3 : 2;
    final rows = (AppThemes.all.length / columns).ceil();
    // Keep the sheet hugging its content on tall screens instead of leaving a
    // large empty area above the grid. Short screens still scroll.
    final contentHeight = 119.0 + rows * tileHeight + (rows - 1) * 12.0;
    final sheetHeight = math.min(media.size.height * 0.86, contentHeight);

    return ListenableBuilder(
      listenable: themeManager,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final selected = themeManager.theme;
        final brightness = Theme.of(context).brightness;

        return Container(
          key: const ValueKey('theme-picker-sheet'),
          height: sheetHeight,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: appBorderSide(cs)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Themes',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('theme-picker-close'),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close theme picker',
                      icon: const Icon(AppIcons.close, size: 20),
                      color: cs.outline,
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.6),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: tileHeight,
                      ),
                      itemCount: AppThemes.all.length,
                      itemBuilder: (context, index) {
                        final theme = AppThemes.all[index];
                        return _ThemePickerCard(
                          theme: theme,
                          selected: theme.id == selected.id,
                          brightness: brightness,
                          onTap: () => themeManager.setTheme(theme),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemePickerCard extends StatelessWidget {
  final AppThemeDefinition theme;
  final bool selected;
  final Brightness brightness;
  final VoidCallback onTap;

  const _ThemePickerCard({
    required this.theme,
    required this.selected,
    required this.brightness,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      label: '${theme.label} theme. ${theme.description}',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        key: ValueKey('app-theme-card-${theme.id}'),
        color: cs.surfaceContainerHigh,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: selected
              ? BorderSide(color: cs.primary, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          key: ValueKey('app-theme-${theme.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ThemeMiniPreview(
                    key: ValueKey('app-theme-preview-${theme.id}'),
                    theme: theme,
                    brightness: brightness,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  theme.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
