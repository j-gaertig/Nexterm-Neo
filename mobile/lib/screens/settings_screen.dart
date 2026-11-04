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
import '../services/account_service.dart';
import '../utils/api_client.dart';
import 'settings/pages/about_page.dart';
import 'settings/pages/account_page.dart';
import 'settings/pages/admin_pages.dart';
import 'settings/pages/api_keys_page.dart';
import 'settings/pages/identities_page.dart';
import 'settings/ui.dart';

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
  AccountProfile? _profile;
  String _query = '';
  String? _profileAccountId;

  @override
  void initState() {
    super.initState();
    _username = widget.authManager.getUsername();
    _fullName = widget.authManager.getFullName();
    widget.authManager.addListener(_onAuthChanged);
    _loadProfile();
  }

  /// Loads name and permissions of the signed-in user. Failures are silent:
  /// the settings stay usable and administration entries simply stay hidden.
  Future<void> _loadProfile() async {
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    final accountId = widget.authManager.accountManager.activeAccount?.id;
    try {
      final profile = await AccountService.getMe(token);
      if (!mounted ||
          accountId != widget.authManager.accountManager.activeAccount?.id) {
        return;
      }
      setState(() {
        _profile = profile;
        _profileAccountId = accountId;
      });
    } catch (_) {
      // Keep whatever we had.
    }
  }

  @override
  void dispose() {
    widget.authManager.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final accountId = widget.authManager.accountManager.activeAccount?.id;
    setState(() {
      _username = widget.authManager.getUsername();
      _fullName = widget.authManager.getFullName();
      if (accountId != _profileAccountId) _profile = null;
    });
    if (accountId != _profileAccountId) _loadProfile();
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

  // --- Navigation helpers --------------------------------------------------

  void _push(WidgetBuilder builder) {
    pushPage<void>(context, builder);
  }

  /// Opens an existing section (appearance, terminal, ...) as its own page.
  void _openSection(
    String title,
    String subtitle,
    List<Widget> Function(ColorScheme cs) section,
  ) {
    _push(
      (_) => Builder(
        builder: (ctx) => SettingsPage(
          title: title,
          subtitle: subtitle,
          // The first element is the old in-page heading; the page header
          // replaces it.
          children: section(Theme.of(ctx).colorScheme).skip(1).toList(),
        ),
      ),
    );
  }

  Future<void> _openAccount() async {
    await pushPage<void>(
      context,
      (_) => AccountPage(authManager: widget.authManager),
    );
    if (mounted) _loadProfile();
  }

  // --- Entries -------------------------------------------------------------

  List<_SettingsGroupData> _groups() {
    final profile = _profile;
    final connections = widget.authManager.accountManager.accounts.length;
    final themeLabel = widget.themeManager.theme.label;
    final admin = <_SettingsEntry>[
      if (profile?.can('settings.monitoring') == true)
        _SettingsEntry(
          icon: AppIcons.chartBox,
          title: 'Monitoring',
          subtitle: 'Status checks, intervals and data retention',
          keywords: 'metrics status interval retention',
          onTap: () => _push(
            (_) => MonitoringSettingsPage(authManager: widget.authManager),
          ),
        ),
      if (profile?.can('settings.engines') == true)
        _SettingsEntry(
          icon: AppIcons.dns,
          title: 'Engines',
          subtitle: 'Connection engines and their status',
          keywords: 'engine connector',
          onTap: () =>
              _push((_) => EnginesPage(authManager: widget.authManager)),
        ),
      if (profile?.can('users.view') == true)
        _SettingsEntry(
          icon: AppIcons.account,
          title: 'Users',
          subtitle: 'Accounts on this Nexterm instance',
          keywords: 'accounts people',
          onTap: () => _push((_) => UsersPage(authManager: widget.authManager)),
        ),
    ];

    return [
      _SettingsGroupData('Account', [
        _SettingsEntry(
          icon: AppIcons.accountCircleOutline,
          title: 'Account',
          subtitle: 'Name, password and two-factor authentication',
          keywords: 'profile name password 2fa totp security session sync',
          onTap: _openAccount,
        ),
        _SettingsEntry(
          icon: AppIcons.key,
          title: 'API keys',
          subtitle: 'Access Nexterm from scripts and tools',
          keywords: 'token api access',
          onTap: () =>
              _push((_) => ApiKeysPage(authManager: widget.authManager)),
        ),
        _SettingsEntry(
          icon: AppIcons.devices,
          title: 'Signed-in devices',
          subtitle: 'Manage devices signed in to your account',
          keywords: 'sessions logout revoke',
          onTap: () =>
              _push((_) => SessionsScreen(authManager: widget.authManager)),
        ),
        _SettingsEntry(
          icon: AppIcons.qrcodeScan,
          title: 'Authorize login',
          subtitle: 'Approve a web login with a QR code',
          keywords: 'qr scan code device',
          onTap: () =>
              _push((_) => QrScannerScreen(authManager: widget.authManager)),
        ),
        _SettingsEntry(
          icon: AppIcons.serverNetwork,
          title: 'Server connections',
          subtitle: connections == 1
              ? '1 connection'
              : '$connections connections',
          keywords: 'instance switch add nexterm server url',
          onTap: () => _push(
            (_) => ServerAccountsScreen(authManager: widget.authManager),
          ),
        ),
      ]),
      _SettingsGroupData('Preferences', [
        _SettingsEntry(
          icon: AppIcons.palette,
          title: 'Appearance',
          subtitle: 'Theme, colors and server list ($themeLabel)',
          keywords: 'theme dark light color palette grid list columns view',
          onTap: () => _openSection(
            'Appearance',
            'Theme, colors and server list',
            _appearanceSection,
          ),
        ),
        _SettingsEntry(
          icon: AppIcons.console,
          title: 'Terminal',
          subtitle: 'Font, colors, keyboard toolbar and password hints',
          keywords: 'font size toolbar keys password prompt color scheme',
          onTap: () => _openSection(
            'Terminal',
            'Font, colors, keyboard toolbar and password hints',
            _terminalSection,
          ),
        ),
        _SettingsEntry(
          icon: AppIcons.folderOutline,
          title: 'File manager',
          subtitle: 'Hidden files, sorting and confirmations',
          keywords: 'sftp files hidden delete sort ios files app',
          onTap: () => _openSection(
            'File manager',
            'Hidden files, sorting and confirmations',
            _fileManagerSection,
          ),
        ),
      ]),
      _SettingsGroupData('Security', [
        _SettingsEntry(
          icon: AppIcons.lockOutline,
          title: 'Screen lock',
          subtitle: _screenLockBusy
              ? 'Waiting for authentication...'
              : widget.screenLockSettings.enabled
              ? 'Required when opening Nexterm'
              : 'Use your device screen lock to open the app',
          keywords: 'biometric fingerprint face pin lock',
          switchValue: widget.screenLockSettings.enabled,
          onSwitch: _screenLockBusy ? null : _handleScreenLockChanged,
        ),
      ]),
      _SettingsGroupData('Library', [
        _SettingsEntry(
          icon: AppIcons.key,
          title: 'Identities',
          subtitle: 'Logins and SSH keys used to connect',
          keywords: 'credentials ssh key password login',
          onTap: () =>
              _push((_) => IdentitiesPage(authManager: widget.authManager)),
        ),
      ]),
      if (admin.isNotEmpty) _SettingsGroupData('Administration', admin),
      _SettingsGroupData('About', [
        _SettingsEntry(
          icon: AppIcons.informationOutline,
          title: 'About Nexterm Neo',
          subtitle: 'Version ${ApiClient.appVersion}, links and licenses',
          keywords: 'version license github help',
          onTap: () => _push((_) => const AboutPage()),
        ),
        if (widget.authManager.isAuthenticated)
          _SettingsEntry(
            icon: AppIcons.exitToApp,
            title: 'Sign out',
            subtitle: 'Sign out of this instance',
            keywords: 'logout',
            destructive: true,
            onTap: _handleLogout,
          ),
      ]),
    ];
  }

  Widget _tileFor(_SettingsEntry e) {
    if (e.onSwitch != null || e.switchValue != null) {
      return ListenableBuilder(
        listenable: widget.screenLockSettings,
        builder: (_, __) => SettingsSwitchTile(
          icon: e.icon,
          title: e.title,
          subtitle: e.subtitle,
          value: widget.screenLockSettings.enabled,
          onChanged: e.onSwitch,
        ),
      );
    }
    return SettingsTile(
      icon: e.icon,
      title: e.title,
      subtitle: e.subtitle,
      destructive: e.destructive,
      onTap: e.onTap,
    );
  }

  Widget _profileCard(ColorScheme cs) {
    final name = _profile?.displayName ?? _fullName ?? _username ?? 'User';
    final handle = _profile?.username ?? _username;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: AppCard(
        onTap: _openAccount,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_profile?.isAdmin == true) ...[
                        const SizedBox(width: 8),
                        const SettingsPill('Admin'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [if (handle != null) '@$handle', _serverLabel].join(' · '),
                    style: TextStyle(fontSize: 12, color: cs.outline),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(AppIcons.chevronRight, size: 18, color: cs.outline),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final navInset = FloatingNavigationBarInset.of(context);
    final query = _query.trim().toLowerCase();
    final groups = _groups();

    final List<Widget> body;
    if (query.isEmpty) {
      body = [
        _profileCard(cs),
        for (final group in groups)
          SettingsGroup(
            title: group.title,
            children: [for (final e in group.entries) _tileFor(e)],
          ),
      ];
    } else {
      final matches = [
        for (final group in groups)
          for (final e in group.entries)
            if (e.matches(query)) e,
      ];
      body = [
        if (matches.isEmpty)
          const SizedBox(
            height: 280,
            child: AppEmptyState(
              icon: AppIcons.magnify,
              title: 'No settings found',
              message: 'Try a different word.',
            ),
          )
        else
          SettingsGroup(
            title: 'Results',
            children: [for (final e in matches) _tileFor(e)],
          ),
      ];
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const ValueKey('settings-list'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + navInset),
          children: [
            const AppPageHeader(
              title: 'Settings',
              padding: EdgeInsets.fromLTRB(4, 16, 4, 12),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration:
                    settingsInputDecoration(
                      context,
                      hint: 'Search settings',
                    ).copyWith(
                      prefixIcon: const Icon(AppIcons.magnify, size: 20),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(AppIcons.close, size: 18),
                              onPressed: () => setState(() => _query = ''),
                            ),
                    ),
              ),
            ),
            ...body,
          ],
        ),
      ),
    );
  }
}

class _SettingsGroupData {
  final String title;
  final List<_SettingsEntry> entries;

  const _SettingsGroupData(this.title, this.entries);
}

class _SettingsEntry {
  final IconData icon;
  final String title;
  final String subtitle;
  final String keywords;
  final VoidCallback? onTap;
  final bool destructive;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitch;

  const _SettingsEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.keywords = '',
    this.onTap,
    this.destructive = false,
    this.switchValue,
    this.onSwitch,
  });

  bool matches(String query) =>
      title.toLowerCase().contains(query) ||
      subtitle.toLowerCase().contains(query) ||
      keywords.contains(query);
}
