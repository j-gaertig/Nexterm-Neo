import 'dart:io';

import 'package:flutter/material.dart';
import '../widgets/app_ui.dart';
import '../widgets/nav_scope.dart';
import 'package:flutter/services.dart';

import '../utils/app_icons.dart';
import '../utils/theme_manager.dart';
import '../utils/auth_manager.dart';
import '../utils/password_prompt_localizations.dart';
import '../utils/screen_lock_settings.dart';
import '../utils/terminal_settings.dart';
import '../utils/sftp_settings.dart';
import '../utils/server_view_settings.dart';
import '../widgets/floating_navigation_bar.dart';
import 'widgets/theme_picker_sheet.dart';
import '../services/api_config.dart';
import '../services/screen_lock_service.dart';
import 'sessions_screen.dart';
import 'server_accounts_screen.dart';
import 'qr_scanner_screen.dart';

part 'settings/sections.dart';
part 'settings/widgets.dart';

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

  String get _serverLabel => ApiConfig.baseUrl
      .replaceFirst(RegExp(r'^https?://'), '')
      .replaceFirst(RegExp(r'/api/?$'), '');

  String _connectionCountLabel() {
    final count = widget.authManager.accountManager.accounts.length;
    return count == 1 ? '1 connection' : '$count connections';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final navInset = FloatingNavigationBarInset.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const ValueKey('settings-list'),
          padding: EdgeInsets.only(bottom: 24 + navInset),
          children: [
            const AppPageHeader(
              title: 'Settings',
              padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
            ),

            ..._accountSection(cs),
            ..._securitySection(cs),
            ..._appearanceSection(cs),
            ..._terminalSection(cs),
            ..._fileManagerSection(cs),
          ],
        ),
      ),
    );
  }
}
