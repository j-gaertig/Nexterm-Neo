part of '../settings_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _SettingsWidgets on _SettingsScreenState {
  Widget _accountProfile(ColorScheme cs, String server) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        AppIconBox(
          icon: AppIcons.account,
          size: 48,
          background: cs.primaryContainer,
          foreground: cs.onPrimaryContainer,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _fullName ?? _username ?? 'User',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  server,
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _section(ColorScheme cs, {required List<Widget> children}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Material(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: appBorderSide(cs),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    ),
  );

  Widget _iconBox(IconData icon) => AppIconBox(icon: icon, size: 36);

  Widget _divider(ColorScheme cs, {double indent = 56, double endIndent = 0}) =>
      Divider(
        height: 1,
        indent: indent,
        endIndent: endIndent,
        color: appBorderColor(cs),
      );

  Widget _navTile(
    IconData icon,
    String title,
    String sub,
    ColorScheme cs,
    VoidCallback onTap,
  ) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _iconBox(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15)),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      sub,
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                  ),
                ],
              ),
            ),
            Icon(AppIcons.chevronRight, color: cs.outlineVariant, size: 18),
          ],
        ),
      ),
    ),
  );

  Widget _logoutTile(ColorScheme cs) => Semantics(
    button: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleLogout,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              AppIconBox(
                icon: AppIcons.exitToApp,
                size: 36,
                background: cs.errorContainer,
                foreground: cs.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Logout',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _themePickerTile(ColorScheme cs) => ListenableBuilder(
    listenable: widget.themeManager,
    builder: (context, _) {
      final theme = widget.themeManager.theme;
      void open() => showThemePickerSheet(context, widget.themeManager);
      return Semantics(
        button: true,
        label: 'Themes, ${theme.label}. Open theme picker',
        excludeSemantics: true,
        onTap: open,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('app-theme-picker'),
            onTap: open,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _iconBox(AppIcons.palette),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Themes',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      theme.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.outline,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    AppIcons.chevronRight,
                    color: cs.outlineVariant,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _colorDot(Color color) => Container(
    width: 10,
    height: 10,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _sectionHeader(String title, ColorScheme cs) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
    child: Semantics(
      header: true,
      container: true,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
      ),
    ),
  );

  Widget _subsectionHeader(String title, ColorScheme cs) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        header: true,
        container: true,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.outline,
          ),
        ),
      ),
    ),
  );
}
