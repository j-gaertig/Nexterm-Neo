import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_icons.dart';
import '../utils/theme_manager.dart';
import '../utils/auth_manager.dart';
import '../utils/password_prompt_localizations.dart';
import '../utils/terminal_settings.dart';
import '../utils/sftp_settings.dart';
import '../utils/server_view_settings.dart';
import '../services/api_config.dart';
import 'sessions_screen.dart';
import 'server_accounts_screen.dart';
import 'qr_scanner_screen.dart';

class _ToolbarGroupTile extends StatelessWidget {
  final int index;
  final ToolbarGroup group;
  final bool enabled;
  final ValueChanged<bool> onToggle;

  const _ToolbarGroupTile({
    super.key,
    required this.index,
    required this.group,
    required this.enabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      child: Row(children: [
        ReorderableDragStartListener(
          index: index,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(AppIcons.dragHorizontalVariant, color: cs.outline, size: 20),
          ),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(group.label, style: const TextStyle(fontSize: 14)),
          Text(group.description, style: TextStyle(fontSize: 12, color: cs.outline)),
        ])),
        Switch(value: enabled, onChanged: onToggle),
      ]),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final ThemeManager themeManager;
  final AuthManager authManager;
  final TerminalSettings terminalSettings;
  final SftpSettings sftpSettings;
  final ServerViewSettings serverViewSettings;

  const SettingsScreen({
    super.key,
    required this.themeManager,
    required this.authManager,
    required this.terminalSettings,
    required this.sftpSettings,
    required this.serverViewSettings,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _username;
  String? _fullName;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  void _loadUserInfo() {
    setState(() {
      _username = widget.authManager.getUsername();
      _fullName = widget.authManager.getFullName();
    });
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Logout')),
        ],
      ),
    );
    if (shouldLogout == true && mounted) await widget.authManager.logout();
  }

  static const MethodChannel _fileProviderChannel =
      MethodChannel('nexterm/fileprovider');

  Future<void> _onExposeToFilesAppChanged(BuildContext context, bool value) async {
    if (!Platform.isIOS) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Only available on iOS'),
          content: const Text(
            'Showing all SFTP/FTP/FTPS servers in the system file manager is only available on iOS. '
            'On Android third-party storage providers are only partially supported.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    try {
      await widget.sftpSettings.setExposeToFilesApp(value);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update Files app integration')),
      );
      return;
    }
    if (!context.mounted) return;
    if (widget.sftpSettings.exposeToFilesApp != value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update Files app integration')),
      );
      return;
    }
    try {
      await _fileProviderChannel.invokeMethod('setExposeEnabled', {'enabled': value});
    } catch (_) {
      try {
        await widget.sftpSettings.setExposeToFilesApp(!value);
      } catch (_) {}
      if (!context.mounted) return;
      final recovered = widget.sftpSettings.exposeToFilesApp == !value;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            recovered
                ? 'Could not update Files app integration'
                : 'Could not update Files app integration (setting may be out of sync)',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final server = ApiConfig.baseUrl.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/api/?$'), '');

    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Text('Settings', style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),

          if (_username != null) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
                  child: Icon(AppIcons.account, color: cs.onPrimaryContainer, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_fullName ?? _username!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Padding(padding: const EdgeInsets.only(top: 2),
                    child: Text(server, style: TextStyle(fontSize: 12, color: cs.outline))),
                ])),
                FilledButton.tonal(
                  onPressed: _handleLogout,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Logout', style: TextStyle(fontSize: 13)),
                ),
              ]),
            ),
          ),

          const SizedBox(height: 8),
          _section(cs, children: [
            _navTile(AppIcons.serverNetwork, 'Connections',
              '${widget.authManager.accountManager.accounts.length} server(s)', cs,
              () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ServerAccountsScreen(authManager: widget.authManager)))),
            Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.3)),
            _navTile(AppIcons.monitor, 'Sessions', 'Manage active sessions', cs,
              () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => SessionsScreen(authManager: widget.authManager)))),
            Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.3)),
            _navTile(AppIcons.qrcodeScan, 'Scan QR Code', 'Authorize a web login', cs,
              () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => QrScannerScreen(authManager: widget.authManager)))),
          ]),

          _sectionHeader('Appearance', cs),
          _section(cs, children: [
            ListenableBuilder(
              listenable: widget.themeManager,
              builder: (_, __) {
                final mode = widget.themeManager.themeMode;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                      child: Icon(AppIcons.themeLightDark, color: cs.onPrimaryContainer, size: 18),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Theme', style: TextStyle(fontSize: 15))),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, icon: Icon(AppIcons.themeSystem, size: 18)),
                        ButtonSegment(value: ThemeMode.light, icon: Icon(AppIcons.lightMode, size: 18)),
                        ButtonSegment(value: ThemeMode.dark, icon: Icon(AppIcons.darkMode, size: 18)),
                      ],
                      selected: {mode},
                      onSelectionChanged: (s) => widget.themeManager.setThemeMode(s.first),
                      showSelectedIcon: false,
                      style: ButtonStyle(visualDensity: VisualDensity.compact),
                    ),
                  ]),
                );
              },
            ),
            Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.3)),
            ListenableBuilder(
              listenable: widget.themeManager,
              builder: (_, __) => SwitchListTile(
                contentPadding: const EdgeInsets.only(left: 16, right: 12),
                secondary: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                  child: Icon(AppIcons.palette, color: cs.onPrimaryContainer, size: 18),
                ),
                title: const Text('Dynamic Color', style: TextStyle(fontSize: 15)),
                subtitle: Text('Use system accent color', style: TextStyle(fontSize: 12, color: cs.outline)),
                value: widget.themeManager.useDynamicColor,
                onChanged: (v) => widget.themeManager.setUseDynamicColor(v),
              ),
            ),
            ListenableBuilder(
              listenable: widget.themeManager,
              builder: (_, __) {
                if (widget.themeManager.useDynamicColor) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Accent Color', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.outline)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 10, runSpacing: 10, children: ThemeManager.accentColorOptions.map((color) {
                      final sel = widget.themeManager.accentColor.toARGB32() == color.toARGB32();
                      return GestureDetector(
                        onTap: () => widget.themeManager.setAccentColor(color),
                        child: Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle,
                            border: sel ? Border.all(color: cs.onSurface, width: 2.5) : null,
                          ),
                          child: sel ? const Icon(AppIcons.check, color: Colors.white, size: 18) : null,
                        ),
                      );
                    }).toList()),
                  ]),
                );
              },
            ),
          ]),

          _sectionHeader('Server List', cs),
          _section(cs, children: [
            ListenableBuilder(
              listenable: widget.serverViewSettings,
              builder: (_, __) {
                final sv = widget.serverViewSettings;
                return Column(children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 340;
                      final label = Expanded(
                        child: Text('View',
                          style: TextStyle(fontSize: 15),
                          overflow: TextOverflow.ellipsis, maxLines: 1, softWrap: false),
                      );
                      final control = SegmentedButton<ServerViewMode>(
                        segments: const [
                          ButtonSegment(value: ServerViewMode.list, icon: Icon(AppIcons.viewList, size: 18), label: Text('List')),
                          ButtonSegment(value: ServerViewMode.grid, icon: Icon(AppIcons.viewGrid, size: 18), label: Text('Grid')),
                        ],
                        selected: {sv.mode},
                        onSelectionChanged: (s) => sv.setMode(s.first),
                        showSelectedIcon: false,
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      );
                      if (narrow) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                                child: Icon(sv.isGrid ? AppIcons.viewGrid : AppIcons.viewList, color: cs.onPrimaryContainer, size: 18),
                              ),
                              const SizedBox(width: 12),
                              label,
                            ]),
                            const SizedBox(height: 10),
                            Align(alignment: Alignment.centerRight, child: control),
                          ]),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                            child: Icon(sv.isGrid ? AppIcons.viewGrid : AppIcons.viewList, color: cs.onPrimaryContainer, size: 18),
                          ),
                          const SizedBox(width: 12),
                          label,
                          control,
                        ]),
                      );
                    },
                  ),
                  if (sv.isGrid) ...[
                    Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.3)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                          child: Icon(AppIcons.viewGrid, color: cs.onPrimaryContainer, size: 18),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Columns',
                            style: TextStyle(fontSize: 15),
                            overflow: TextOverflow.ellipsis, maxLines: 1, softWrap: false),
                        ),
                        Text('${sv.gridColumns}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.outline)),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(children: [
                        IconButton(
                          icon: Icon(AppIcons.minus, size: 18),
                          tooltip: 'Fewer columns',
                          onPressed: sv.gridColumns > ServerViewSettings.minColumns
                              ? () => sv.setGridColumns(sv.gridColumns - 1)
                              : null,
                        ),
                        Expanded(
                          child: Slider(
                            value: sv.gridColumns.toDouble(),
                            min: ServerViewSettings.minColumns.toDouble(),
                            max: ServerViewSettings.maxColumns.toDouble(),
                            divisions: ServerViewSettings.maxColumns - ServerViewSettings.minColumns,
                            semanticFormatterCallback: (v) => '${v.round()} columns',
                            onChanged: (v) => sv.setGridColumns(v.round()),
                          ),
                        ),
                        IconButton(
                          icon: Icon(AppIcons.plus, size: 18),
                          tooltip: 'More columns',
                          onPressed: sv.gridColumns < ServerViewSettings.maxColumns
                              ? () => sv.setGridColumns(sv.gridColumns + 1)
                              : null,
                        ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                  ],
                ]);
              },
            ),
          ]),

          _sectionHeader('Terminal', cs),
          _section(cs, children: [
            ListenableBuilder(
              listenable: widget.terminalSettings,
              builder: (_, __) {
                final ts = widget.terminalSettings;
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                        child: Icon(AppIcons.formatSize, color: cs.onPrimaryContainer, size: 18),
                      ),
                      const SizedBox(width: 12),
                      const Text('Font Size', style: TextStyle(fontSize: 15)),
                      const Spacer(),
                      Text('${ts.fontSize.toInt()} pt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.outline)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      IconButton(icon: Icon(AppIcons.minus, size: 18), onPressed: ts.fontSize > 8 ? () => ts.setFontSize(ts.fontSize - 1) : null),
                      Expanded(child: Slider(value: ts.fontSize, min: 8, max: 24, divisions: 16, onChanged: (v) => ts.setFontSize(v))),
                      IconButton(icon: Icon(AppIcons.plus, size: 18), onPressed: ts.fontSize < 24 ? () => ts.setFontSize(ts.fontSize + 1) : null),
                    ]),
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant.withValues(alpha: 0.3)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Align(alignment: Alignment.centerLeft,
                      child: Text('Color Theme', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.outline))),
                  ),
                  SizedBox(
                    height: 72,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      itemCount: TerminalThemes.all.length,
                      itemBuilder: (_, i) {
                        final t = TerminalThemes.all[i];
                        final sel = ts.themeId == t.id;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            onTap: () => ts.setTheme(t.id),
                            child: Container(
                              width: 80,
                              decoration: BoxDecoration(
                                color: t.background, borderRadius: BorderRadius.circular(10),
                                border: sel
                                    ? Border.all(color: cs.primary, width: 2.5)
                                    : Border.all(color: cs.outlineVariant, width: 1),
                              ),
                              padding: const EdgeInsets.all(6),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  _colorDot(t.theme.red), _colorDot(t.theme.green),
                                  _colorDot(t.theme.yellow), _colorDot(t.theme.blue),
                                ]),
                                const SizedBox(height: 4),
                                Text(t.name, style: TextStyle(color: t.foreground, fontSize: 10, fontWeight: FontWeight.w600),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant.withValues(alpha: 0.3)),
                  Builder(builder: (innerContext) {
                    // Mirrors web `settings.terminal.input.passwordPromptDetection`
                    // (Enabled/Disabled dropdown) as a native switch.
                    final strings = PasswordPromptLocalizations.of(innerContext);
                    return SwitchListTile(
                      contentPadding: const EdgeInsets.only(left: 16, right: 12),
                      secondary: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                        child: Icon(AppIcons.key, color: cs.onPrimaryContainer, size: 18),
                      ),
                      title: Text(strings.settingTitle, style: const TextStyle(fontSize: 15)),
                      subtitle: Text(
                        ts.passwordPromptDetection ? strings.enabled : strings.disabled,
                        style: TextStyle(fontSize: 12, color: cs.outline),
                      ),
                      value: ts.passwordPromptDetection,
                      onChanged: (v) => ts.setPasswordPromptDetection(v),
                    );
                  }),
                ]);
              },
            ),
          ]),
          const SizedBox(height: 4),
          _section(cs, children: [
            ListenableBuilder(
              listenable: widget.terminalSettings,
              builder: (_, __) {
                final ts = widget.terminalSettings;
                final order = ts.groupOrder.toList();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text('Keyboard Toolbar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.outline)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text('Toggle and drag to reorder', style: TextStyle(fontSize: 12, color: cs.outline.withValues(alpha: 0.7))),
                  ),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: order.length,
                    proxyDecorator: (child, _, __) => Material(elevation: 4, borderRadius: BorderRadius.circular(12), child: child),
                    onReorder: (o, n) {
                      if (n > o) n--;
                      final item = order.removeAt(o);
                      order.insert(n, item);
                      ts.setGroupOrder(order);
                    },
                    itemBuilder: (_, i) {
                      final g = order[i];
                      return _ToolbarGroupTile(key: ValueKey(g), index: i, group: g, enabled: ts.isGroupEnabled(g), onToggle: (v) => ts.setGroupEnabled(g, v));
                    },
                  ),
                ]);
              },
            ),
          ]),

          _sectionHeader('File Browser', cs),
          _section(cs, children: [
            ListenableBuilder(
              listenable: widget.sftpSettings,
              builder: (_, __) {
                final sf = widget.sftpSettings;
                return Column(children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.only(left: 16, right: 12),
                    secondary: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                      child: Icon(AppIcons.fileHidden, color: cs.onPrimaryContainer, size: 18),
                    ),
                    title: const Text('Show Hidden Files', style: TextStyle(fontSize: 15)),
                    subtitle: Text('Show files starting with .', style: TextStyle(fontSize: 12, color: cs.outline)),
                    value: sf.showHiddenFiles,
                    onChanged: (v) => sf.setShowHiddenFiles(v),
                  ),
                  Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.3)),
                  if (sf.showHiddenFiles)
                    SwitchListTile(
                      contentPadding: const EdgeInsets.only(left: 16, right: 12),
                      secondary: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                        child: Icon(AppIcons.opacity, color: cs.onPrimaryContainer, size: 18),
                      ),
                      title: const Text('Dim Hidden Files', style: TextStyle(fontSize: 15)),
                      subtitle: Text('Display hidden files with reduced opacity.', style: TextStyle(fontSize: 12, color: cs.outline)),
                      value: sf.dimHiddenFiles,
                      onChanged: (v) => sf.setDimHiddenFiles(v),
                    ),
                  if (sf.showHiddenFiles)
                    Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.3)),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.only(left: 16, right: 12),
                    secondary: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                      child: Icon(AppIcons.deleteAlert, color: cs.onPrimaryContainer, size: 18),
                    ),
                    title: const Text('Confirm Before Delete', style: TextStyle(fontSize: 15)),
                    value: sf.confirmBeforeDelete,
                    onChanged: (v) => sf.setConfirmBeforeDelete(v),
                  ),
                  Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.3)),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.only(left: 16, right: 12),
                    secondary: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                      child: Icon(AppIcons.folderArrowUp, color: cs.onPrimaryContainer, size: 18),
                    ),
                    title: const Text('Sort Folders First', style: TextStyle(fontSize: 15)),
                    value: sf.sortFoldersFirst,
                    onChanged: (v) => sf.setSortFoldersFirst(v),
                  ),
                  Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.3)),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.only(left: 16, right: 12),
                    secondary: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                      child: Icon(AppIcons.folderMultipleOutline, color: cs.onPrimaryContainer, size: 18),
                    ),
                    title: const Text('Show Servers in Files App', style: TextStyle(fontSize: 15)),
                    subtitle: Text(
                      Platform.isIOS
                          ? 'Prepares all SFTP/FTP/FTPS servers for the iOS Files app integration'
                          : 'Only available on iOS',
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                    value: Platform.isIOS && sf.exposeToFilesApp,
                    onChanged: (v) => _onExposeToFilesAppChanged(context, v),
                  ),
                  Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.3)),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.only(left: 16, right: 12),
                    secondary: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                      child: Icon(AppIcons.alertOutline, color: cs.onPrimaryContainer, size: 18),
                    ),
                    title: const Text('Warn Before Discarding', style: TextStyle(fontSize: 15)),
                    subtitle: Text(
                      'Warn before replacing a file that is still open in an external editor',
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                    value: sf.warnBeforeDiscardEdit,
                    onChanged: (v) => sf.setWarnBeforeDiscardEdit(v),
                  ),
                ]);
              },
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _section(ColorScheme cs, {required List<Widget> children}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
      child: Column(children: children),
    ),
  );

  Widget _navTile(IconData icon, String title, String sub, ColorScheme cs, VoidCallback onTap) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: cs.onPrimaryContainer, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15)),
            Padding(padding: const EdgeInsets.only(top: 2),
              child: Text(sub, style: TextStyle(fontSize: 12, color: cs.outline))),
          ])),
          Icon(AppIcons.chevronRight, color: cs.outlineVariant, size: 18),
        ]),
      ),
    ),
  );

  Widget _colorDot(Color color) => Container(
    width: 10, height: 10, margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _sectionHeader(String title, ColorScheme cs) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
    child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary)),
  );
}
