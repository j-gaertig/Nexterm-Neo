part of '../settings_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _SettingsSections on _SettingsScreenState {
  List<Widget> _accountSection(ColorScheme cs) => [
    _sectionHeader('Account', cs),
    _section(
      cs,
      children: [
        if (widget.authManager.isAuthenticated) ...[
          _accountProfile(cs, _serverLabel),
          _divider(cs),
        ],
        _navTile(
          AppIcons.serverNetwork,
          'Server Connections',
          _connectionCountLabel(),
          cs,
          () => pushPage(
            context,
            (_) => ServerAccountsScreen(authManager: widget.authManager),
          ),
        ),
        if (widget.authManager.isAuthenticated) ...[
          _divider(cs),
          _logoutTile(cs),
        ],
      ],
    ),
  ];

  List<Widget> _securitySection(ColorScheme cs) => [
    _sectionHeader('Security', cs),
    _section(
      cs,
      children: [
        ListenableBuilder(
          listenable: widget.screenLockSettings,
          builder: (_, __) => SwitchListTile(
            contentPadding: const EdgeInsets.only(left: 16, right: 12),
            secondary: _iconBox(AppIcons.lockOutline),
            title: const Text('Screen Lock', style: TextStyle(fontSize: 15)),
            subtitle: Text(
              _screenLockBusy
                  ? 'Waiting for authentication...'
                  : widget.screenLockSettings.enabled
                  ? 'Required when opening Nexterm'
                  : 'Use your device screen lock to open the app',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
            value: widget.screenLockSettings.enabled,
            onChanged: _screenLockBusy ? null : _handleScreenLockChanged,
          ),
        ),
        _divider(cs),
        _navTile(
          AppIcons.devices,
          'Signed-in Devices',
          'Manage devices signed in to your account',
          cs,
          () => pushPage(
            context,
            (_) => SessionsScreen(authManager: widget.authManager),
          ),
        ),
        _divider(cs),
        _navTile(
          AppIcons.qrcodeScan,
          'Authorize Login',
          'Approve a web login with a QR code',
          cs,
          () => pushPage(
            context,
            (_) => QrScannerScreen(authManager: widget.authManager),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _appearanceSection(ColorScheme cs) => [
    _sectionHeader('Appearance', cs),
    _section(
      cs,
      children: [
        ListenableBuilder(
          listenable: widget.themeManager,
          builder: (_, __) {
            final mode = widget.themeManager.themeMode;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _iconBox(AppIcons.themeLightDark),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Mode', style: TextStyle(fontSize: 15)),
                  ),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(
                          AppIcons.themeSystem,
                          size: 18,
                          semanticLabel: 'System theme',
                        ),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(
                          AppIcons.lightMode,
                          size: 18,
                          semanticLabel: 'Light theme',
                        ),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(
                          AppIcons.darkMode,
                          size: 18,
                          semanticLabel: 'Dark theme',
                        ),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) =>
                        widget.themeManager.setThemeMode(s.first),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        _divider(cs),
        _themePickerTile(cs),
        _divider(cs),
        ListenableBuilder(
          listenable: widget.serverViewSettings,
          builder: (_, __) {
            final sv = widget.serverViewSettings;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 340;
                    final label = Expanded(
                      child: Text(
                        'Layout',
                        style: TextStyle(fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    );
                    final control = SegmentedButton<ServerViewMode>(
                      segments: const [
                        ButtonSegment(
                          value: ServerViewMode.list,
                          icon: Icon(AppIcons.viewList, size: 18),
                          label: Text('List'),
                        ),
                        ButtonSegment(
                          value: ServerViewMode.grid,
                          icon: Icon(AppIcons.viewGrid, size: 18),
                          label: Text('Grid'),
                        ),
                      ],
                      selected: {sv.mode},
                      onSelectionChanged: (s) => sv.setMode(s.first),
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                    if (narrow) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _iconBox(
                                  sv.isGrid
                                      ? AppIcons.viewGrid
                                      : AppIcons.viewList,
                                ),
                                const SizedBox(width: 12),
                                label,
                              ],
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: control,
                            ),
                          ],
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          _iconBox(
                            sv.isGrid ? AppIcons.viewGrid : AppIcons.viewList,
                          ),
                          const SizedBox(width: 12),
                          label,
                          control,
                        ],
                      ),
                    );
                  },
                ),
                if (sv.isGrid) ...[
                  _divider(cs),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        _iconBox(AppIcons.viewGrid),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Columns',
                                style: TextStyle(fontSize: 15),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                softWrap: false,
                              ),
                              Text(
                                'Preferred columns, adapted to screen width',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${sv.gridColumns}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(AppIcons.minus, size: 18),
                          tooltip: 'Fewer columns',
                          onPressed:
                              sv.gridColumns > ServerViewSettings.minColumns
                              ? () => sv.setGridColumns(sv.gridColumns - 1)
                              : null,
                        ),
                        Expanded(
                          child: Slider(
                            value: sv.gridColumns.toDouble(),
                            min: ServerViewSettings.minColumns.toDouble(),
                            max: ServerViewSettings.maxColumns.toDouble(),
                            divisions:
                                ServerViewSettings.maxColumns -
                                ServerViewSettings.minColumns,
                            label: '${sv.gridColumns}',
                            semanticFormatterCallback: (v) =>
                                '${v.round()} columns',
                            onChanged: (v) => sv.setGridColumns(v.round()),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(AppIcons.plus, size: 18),
                          tooltip: 'More columns',
                          onPressed:
                              sv.gridColumns < ServerViewSettings.maxColumns
                              ? () => sv.setGridColumns(sv.gridColumns + 1)
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ],
            );
          },
        ),
      ],
    ),
  ];

  List<Widget> _terminalSection(ColorScheme cs) => [
    _sectionHeader('Terminal', cs),
    _section(
      cs,
      children: [
        ListenableBuilder(
          listenable: widget.terminalSettings,
          builder: (_, __) {
            final ts = widget.terminalSettings;
            final order = ts.groupOrder.toList();
            final themeCardScale =
                (MediaQuery.textScalerOf(context).scale(10) / 10).clamp(
                  1.0,
                  4.0,
                );
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      _iconBox(AppIcons.formatSize),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Font Size',
                          style: TextStyle(fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${ts.fontSize.toInt()} pt',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(AppIcons.minus, size: 18),
                        tooltip: 'Decrease font size',
                        onPressed: ts.fontSize > 8
                            ? () => ts.setFontSize(ts.fontSize - 1)
                            : null,
                      ),
                      Expanded(
                        child: Slider(
                          value: ts.fontSize,
                          min: 8,
                          max: 24,
                          divisions: 16,
                          label: '${ts.fontSize.round()} pt',
                          semanticFormatterCallback: (v) =>
                              '${v.round()} points',
                          onChanged: (v) => ts.setFontSize(v),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(AppIcons.plus, size: 18),
                        tooltip: 'Increase font size',
                        onPressed: ts.fontSize < 24
                            ? () => ts.setFontSize(ts.fontSize + 1)
                            : null,
                      ),
                    ],
                  ),
                ),
                _divider(cs, indent: 16, endIndent: 16),
                _subsectionHeader('Terminal Theme', cs),
                SizedBox(
                  height: 72 * themeCardScale,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    itemCount: TerminalThemes.all.length,
                    itemBuilder: (_, i) {
                      final t = TerminalThemes.all[i];
                      final selected = ts.themeId == t.id;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Semantics(
                          button: true,
                          selected: selected,
                          label: '${t.name} terminal theme',
                          excludeSemantics: true,
                          onTap: () => ts.setTheme(t.id),
                          child: GestureDetector(
                            onTap: () => ts.setTheme(t.id),
                            child: Container(
                              width: 80,
                              decoration: BoxDecoration(
                                color: t.background,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.tile,
                                ),
                                border: selected
                                    ? Border.all(color: cs.primary, width: 2.5)
                                    : Border.all(
                                        color: appBorderColor(cs),
                                        width: 1,
                                      ),
                              ),
                              padding: const EdgeInsets.all(6),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _colorDot(t.theme.red),
                                      _colorDot(t.theme.green),
                                      _colorDot(t.theme.yellow),
                                      _colorDot(t.theme.blue),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    t.name,
                                    style: TextStyle(
                                      color: t.foreground,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                _divider(cs, indent: 16, endIndent: 16),
                _subsectionHeader('Keyboard Toolbar', cs),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Toggle and drag to reorder',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.outline.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: order.length,
                  proxyDecorator: (child, _, __) => Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: child,
                  ),
                  onReorderItem: (o, n) {
                    final item = order.removeAt(o);
                    order.insert(n, item);
                    ts.setGroupOrder(order);
                  },
                  itemBuilder: (_, i) {
                    final g = order[i];
                    return _ToolbarGroupTile(
                      key: ValueKey(g),
                      index: i,
                      group: g,
                      enabled: ts.isGroupEnabled(g),
                      onToggle: (v) => ts.setGroupEnabled(g, v),
                    );
                  },
                ),
                _divider(cs, indent: 16, endIndent: 16),
                Builder(
                  builder: (innerContext) {
                    // Mirrors web `settings.terminal.input.passwordPromptDetection`
                    // as a native switch. The switch state already says whether
                    // the feature is enabled, so no extra status subtitle.
                    final strings = PasswordPromptLocalizations.of(
                      innerContext,
                    );
                    return SwitchListTile(
                      contentPadding: const EdgeInsets.only(
                        left: 16,
                        right: 12,
                      ),
                      secondary: _iconBox(AppIcons.key),
                      title: Text(
                        strings.settingTitle,
                        style: const TextStyle(fontSize: 15),
                      ),
                      value: ts.passwordPromptDetection,
                      onChanged: (v) => ts.setPasswordPromptDetection(v),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ],
    ),
  ];

  List<Widget> _fileManagerSection(ColorScheme cs) => [
    _sectionHeader('File Manager', cs),
    _section(
      cs,
      children: [
        ListenableBuilder(
          listenable: widget.sftpSettings,
          builder: (_, __) {
            final sf = widget.sftpSettings;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.only(left: 16, right: 12),
                  secondary: _iconBox(AppIcons.fileHidden),
                  title: const Text(
                    'Show Hidden Files',
                    style: TextStyle(fontSize: 15),
                  ),
                  subtitle: Text(
                    'Show files that start with a dot',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                  value: sf.showHiddenFiles,
                  onChanged: (v) => sf.setShowHiddenFiles(v),
                ),
                _divider(cs),
                SwitchListTile(
                  contentPadding: const EdgeInsets.only(left: 16, right: 12),
                  secondary: _iconBox(AppIcons.folderArrowUp),
                  title: const Text(
                    'Sort Folders First',
                    style: TextStyle(fontSize: 15),
                  ),
                  subtitle: Text(
                    'Keep folders at the top of each list.',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                  value: sf.sortFoldersFirst,
                  onChanged: (v) => sf.setSortFoldersFirst(v),
                ),
                _divider(cs),
                SwitchListTile(
                  contentPadding: const EdgeInsets.only(left: 16, right: 12),
                  secondary: _iconBox(AppIcons.deleteAlert),
                  title: const Text(
                    'Confirm Before Delete',
                    style: TextStyle(fontSize: 15),
                  ),
                  subtitle: Text(
                    'Ask before deleting files.',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                  value: sf.confirmBeforeDelete,
                  onChanged: (v) => sf.setConfirmBeforeDelete(v),
                ),
                _divider(cs),
                SwitchListTile(
                  contentPadding: const EdgeInsets.only(left: 16, right: 12),
                  secondary: _iconBox(AppIcons.alertOutline),
                  title: const Text(
                    'Warn Before Discarding',
                    style: TextStyle(fontSize: 15),
                  ),
                  subtitle: Text(
                    'Warn before replacing a file that is still open in an external editor',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                  value: sf.warnBeforeDiscardEdit,
                  onChanged: (v) => sf.setWarnBeforeDiscardEdit(v),
                ),
                if (Platform.isIOS) ...[
                  _divider(cs),
                  _subsectionHeader('iOS Integration', cs),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.only(left: 16, right: 12),
                    secondary: _iconBox(AppIcons.folderMultipleOutline),
                    title: const Text(
                      'Show in Files App',
                      style: TextStyle(fontSize: 15),
                    ),
                    subtitle: Text(
                      'Expose SFTP/FTP/FTPS servers to the iOS Files app',
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                    value: sf.exposeToFilesApp,
                    onChanged: (v) => _onExposeToFilesAppChanged(context, v),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    ),
  ];
}
