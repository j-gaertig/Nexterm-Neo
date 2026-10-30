import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_icons.dart';
import '../utils/theme_manager.dart';
import '../utils/auth_manager.dart';
import '../utils/password_prompt_localizations.dart';
import '../utils/screen_lock_settings.dart';
import '../utils/terminal_settings.dart';
import '../utils/sftp_settings.dart';
import '../utils/server_view_settings.dart';
import '../services/api_config.dart';
import '../services/screen_lock_service.dart';
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
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(
                AppIcons.dragHorizontalVariant,
                color: cs.outline,
                size: 20,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.label, style: const TextStyle(fontSize: 14)),
                Text(
                  group.description,
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onToggle),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final ThemeManager themeManager;
  final AuthManager authManager;
  final TerminalSettings terminalSettings;
  final SftpSettings sftpSettings;
  final ServerViewSettings serverViewSettings;
  final ScreenLockSettings screenLockSettings;
  final ScreenLockService screenLockService;

  const SettingsScreen({
    super.key,
    required this.themeManager,
    required this.authManager,
    required this.terminalSettings,
    required this.sftpSettings,
    required this.serverViewSettings,
    required this.screenLockSettings,
    required this.screenLockService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _username;
  String? _fullName;
  bool _screenLockBusy = false;

  @override
  void initState() {
    super.initState();
    _username = widget.authManager.getUsername();
    _fullName = widget.authManager.getFullName();
    widget.authManager.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    widget.authManager.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    setState(() {
      _username = widget.authManager.getUsername();
      _fullName = widget.authManager.getFullName();
    });
  }

  Future<void> _handleScreenLockChanged(bool value) async {
    if (_screenLockBusy) return;

    setState(() => _screenLockBusy = true);
    try {
      if (value) {
        final supported = await widget.screenLockService.isDeviceSupported();
        if (!mounted) return;
        if (!supported) {
          await _showScreenLockUnavailableDialog();
          return;
        }

        final result = await widget.screenLockService.authenticate(
          reason: 'Authenticate to enable screen lock for Nexterm.',
        );
        if (!mounted) return;
        if (result != ScreenLockAuthResult.success) {
          _showScreenLockMessage(result.message);
          return;
        }

        await widget.screenLockSettings.setEnabled(true);
        if (!mounted) return;
        _showScreenLockMessage(
          widget.screenLockSettings.enabled
              ? 'Screen lock enabled.'
              : 'Could not save screen lock setting.',
        );
        return;
      }

      final result = await widget.screenLockService.authenticate(
        reason: 'Authenticate to disable screen lock for Nexterm.',
      );
      if (!mounted) return;
      if (result == ScreenLockAuthResult.success) {
        await widget.screenLockSettings.setEnabled(false);
        if (!mounted) return;
        _showScreenLockMessage(
          !widget.screenLockSettings.enabled
              ? 'Screen lock disabled.'
              : 'Could not save screen lock setting.',
        );
        return;
      }
      if (result != ScreenLockAuthResult.canceled) {
        _showScreenLockMessage(result.message);
      }
    } catch (_) {
      if (mounted) {
        _showScreenLockMessage('Could not update screen lock setting.');
      }
    } finally {
      if (mounted) setState(() => _screenLockBusy = false);
    }
  }

  void _showScreenLockMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showScreenLockUnavailableDialog() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Screen lock unavailable'),
        content: const Text(
          'Set up a screen lock (PIN, pattern, password, or biometrics) in your device settings, then try again.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (shouldLogout == true && mounted) await widget.authManager.logout();
  }

  static const MethodChannel _fileProviderChannel = MethodChannel(
    'nexterm/fileprovider',
  );

  Future<void> _onExposeToFilesAppChanged(
    BuildContext context,
    bool value,
  ) async {
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
      await _fileProviderChannel.invokeMethod('setExposeEnabled', {
        'enabled': value,
      });
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

  String _connectionCountLabel() {
    final count = widget.authManager.accountManager.accounts.length;
    return count == 1 ? '1 connection' : '$count connections';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final server = ApiConfig.baseUrl
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'/api/?$'), '');

    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const ValueKey('settings-list'),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Text(
                'Settings',
                style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),

            _sectionHeader('Account', cs),
            _section(
              cs,
              children: [
                if (widget.authManager.isAuthenticated) ...[
                  _accountProfile(cs, server),
                  _divider(cs),
                ],
                _navTile(
                  AppIcons.serverNetwork,
                  'Server Connections',
                  _connectionCountLabel(),
                  cs,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ServerAccountsScreen(authManager: widget.authManager),
                    ),
                  ),
                ),
                if (widget.authManager.isAuthenticated) ...[
                  _divider(cs),
                  _logoutTile(cs),
                ],
              ],
            ),

            _sectionHeader('Security', cs),
            _section(
              cs,
              children: [
                ListenableBuilder(
                  listenable: widget.screenLockSettings,
                  builder: (_, __) => SwitchListTile(
                    contentPadding: const EdgeInsets.only(left: 16, right: 12),
                    secondary: _iconBox(AppIcons.lockOutline, cs),
                    title: const Text(
                      'Screen Lock',
                      style: TextStyle(fontSize: 15),
                    ),
                    subtitle: Text(
                      _screenLockBusy
                          ? 'Waiting for authentication...'
                          : widget.screenLockSettings.enabled
                          ? 'Required when opening Nexterm'
                          : 'Use your device screen lock to open the app',
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                    value: widget.screenLockSettings.enabled,
                    onChanged: _screenLockBusy
                        ? null
                        : _handleScreenLockChanged,
                  ),
                ),
                _divider(cs),
                _navTile(
                  AppIcons.devices,
                  'Signed-in Devices',
                  'Manage devices signed in to your account',
                  cs,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SessionsScreen(authManager: widget.authManager),
                    ),
                  ),
                ),
                _divider(cs),
                _navTile(
                  AppIcons.qrcodeScan,
                  'Authorize Login',
                  'Approve a web login with a QR code',
                  cs,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          QrScannerScreen(authManager: widget.authManager),
                    ),
                  ),
                ),
              ],
            ),

            _sectionHeader('Appearance', cs),
            _section(
              cs,
              children: [
                ListenableBuilder(
                  listenable: widget.themeManager,
                  builder: (_, __) {
                    final mode = widget.themeManager.themeMode;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          _iconBox(AppIcons.themeLightDark, cs),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Theme',
                              style: TextStyle(fontSize: 15),
                            ),
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
                ListenableBuilder(
                  listenable: widget.themeManager,
                  builder: (_, __) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SwitchListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 16,
                          right: 12,
                        ),
                        secondary: _iconBox(AppIcons.palette, cs),
                        title: const Text(
                          'Dynamic Color',
                          style: TextStyle(fontSize: 15),
                        ),
                        subtitle: Text(
                          'Use system accent color',
                          style: TextStyle(fontSize: 12, color: cs.outline),
                        ),
                        value: widget.themeManager.useDynamicColor,
                        onChanged: (v) =>
                            widget.themeManager.setUseDynamicColor(v),
                      ),
                      if (!widget.themeManager.useDynamicColor) ...[
                        _divider(cs),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Accent Color',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: cs.outline,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: ThemeManager.accentColorOptions
                                    .asMap()
                                    .entries
                                    .map((entry) {
                                      final color = entry.value;
                                      final selected =
                                          widget.themeManager.accentColor
                                              .toARGB32() ==
                                          color.toARGB32();
                                      return Semantics(
                                        button: true,
                                        selected: selected,
                                        label: 'Accent color ${entry.key + 1}',
                                        child: InkResponse(
                                          onTap: () => widget.themeManager
                                              .setAccentColor(color),
                                          radius: 24,
                                          child: SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: Center(
                                              child: Container(
                                                width: 38,
                                                height: 38,
                                                decoration: BoxDecoration(
                                                  color: color,
                                                  shape: BoxShape.circle,
                                                  border: selected
                                                      ? Border.all(
                                                          color: cs.onSurface,
                                                          width: 2.5,
                                                        )
                                                      : null,
                                                ),
                                                child: selected
                                                    ? const Icon(
                                                        AppIcons.check,
                                                        color: Colors.white,
                                                        size: 18,
                                                      )
                                                    : null,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    })
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _divider(cs),
                _subsectionHeader('Server List', cs),
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
                                'Default View',
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
                                          cs,
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
                                    sv.isGrid
                                        ? AppIcons.viewGrid
                                        : AppIcons.viewList,
                                    cs,
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
                                _iconBox(AppIcons.viewGrid, cs),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                      sv.gridColumns >
                                          ServerViewSettings.minColumns
                                      ? () => sv.setGridColumns(
                                          sv.gridColumns - 1,
                                        )
                                      : null,
                                ),
                                Expanded(
                                  child: Slider(
                                    value: sv.gridColumns.toDouble(),
                                    min: ServerViewSettings.minColumns
                                        .toDouble(),
                                    max: ServerViewSettings.maxColumns
                                        .toDouble(),
                                    divisions:
                                        ServerViewSettings.maxColumns -
                                        ServerViewSettings.minColumns,
                                    label: '${sv.gridColumns}',
                                    semanticFormatterCallback: (v) =>
                                        '${v.round()} columns',
                                    onChanged: (v) =>
                                        sv.setGridColumns(v.round()),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(AppIcons.plus, size: 18),
                                  tooltip: 'More columns',
                                  onPressed:
                                      sv.gridColumns <
                                          ServerViewSettings.maxColumns
                                      ? () => sv.setGridColumns(
                                          sv.gridColumns + 1,
                                        )
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
                              _iconBox(AppIcons.formatSize, cs),
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
                        _subsectionHeader('Color Theme', cs),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
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
                                        borderRadius: BorderRadius.circular(10),
                                        border: selected
                                            ? Border.all(
                                                color: cs.primary,
                                                width: 2.5,
                                              )
                                            : Border.all(
                                                color: cs.outlineVariant,
                                                width: 1,
                                              ),
                                      ),
                                      padding: const EdgeInsets.all(6),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
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
                        Builder(
                          builder: (innerContext) {
                            // Mirrors web `settings.terminal.input.passwordPromptDetection`
                            // (Enabled/Disabled dropdown) as a native switch.
                            final strings = PasswordPromptLocalizations.of(
                              innerContext,
                            );
                            return SwitchListTile(
                              contentPadding: const EdgeInsets.only(
                                left: 16,
                                right: 12,
                              ),
                              secondary: _iconBox(AppIcons.key, cs),
                              title: Text(
                                strings.settingTitle,
                                style: const TextStyle(fontSize: 15),
                              ),
                              subtitle: Text(
                                ts.passwordPromptDetection
                                    ? strings.enabled
                                    : strings.disabled,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.outline,
                                ),
                              ),
                              value: ts.passwordPromptDetection,
                              onChanged: (v) =>
                                  ts.setPasswordPromptDetection(v),
                            );
                          },
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
                          onReorder: (o, n) {
                            if (n > o) n--;
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
                      ],
                    );
                  },
                ),
              ],
            ),

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
                          contentPadding: const EdgeInsets.only(
                            left: 16,
                            right: 12,
                          ),
                          secondary: _iconBox(AppIcons.fileHidden, cs),
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
                        if (sf.showHiddenFiles) ...[
                          _divider(cs),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.only(
                              left: 16,
                              right: 12,
                            ),
                            secondary: _iconBox(AppIcons.opacity, cs),
                            title: const Text(
                              'Dim Hidden Files',
                              style: TextStyle(fontSize: 15),
                            ),
                            subtitle: Text(
                              'Display hidden files with reduced opacity.',
                              style: TextStyle(fontSize: 12, color: cs.outline),
                            ),
                            value: sf.dimHiddenFiles,
                            onChanged: (v) => sf.setDimHiddenFiles(v),
                          ),
                        ],
                        _divider(cs),
                        SwitchListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 16,
                            right: 12,
                          ),
                          secondary: _iconBox(AppIcons.folderArrowUp, cs),
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
                          contentPadding: const EdgeInsets.only(
                            left: 16,
                            right: 12,
                          ),
                          secondary: _iconBox(AppIcons.deleteAlert, cs),
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
                          contentPadding: const EdgeInsets.only(
                            left: 16,
                            right: 12,
                          ),
                          secondary: _iconBox(AppIcons.alertOutline, cs),
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
                            contentPadding: const EdgeInsets.only(
                              left: 16,
                              right: 12,
                            ),
                            secondary: _iconBox(
                              AppIcons.folderMultipleOutline,
                              cs,
                            ),
                            title: const Text(
                              'Show in Files App',
                              style: TextStyle(fontSize: 15),
                            ),
                            subtitle: Text(
                              'Expose SFTP/FTP/FTPS servers to the iOS Files app',
                              style: TextStyle(fontSize: 12, color: cs.outline),
                            ),
                            value: sf.exposeToFilesApp,
                            onChanged: (v) =>
                                _onExposeToFilesAppChanged(context, v),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountProfile(ColorScheme cs, String server) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(AppIcons.account, color: cs.onPrimaryContainer, size: 24),
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
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    ),
  );

  Widget _iconBox(IconData icon, ColorScheme cs) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: cs.primaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, color: cs.onPrimaryContainer, size: 18),
  );

  Widget _divider(ColorScheme cs, {double indent = 56, double endIndent = 0}) =>
      Divider(
        height: 1,
        indent: indent,
        endIndent: endIndent,
        color: cs.outlineVariant.withValues(alpha: 0.3),
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
            _iconBox(icon, cs),
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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  AppIcons.exitToApp,
                  color: cs.onErrorContainer,
                  size: 18,
                ),
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
