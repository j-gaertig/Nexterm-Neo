import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../account/account_models.dart';
import '../../api/nexterm_api.dart';
import '../../auth/session_store.dart';
import '../../settings/app_settings.dart';
import '../../settings/settings_widgets.dart';
import 'settings_apikeys_page.dart';
import 'settings_audit_page.dart';
import 'settings_identities_page.dart';
import 'settings_link_device_page.dart';
import 'settings_monitoring_page.dart';
import 'settings_totp_page.dart';

/// Settings hub: account + server settings (web parity) + app prefs.
///
/// Groups: Account (profile, name, password), Server (identities,
/// monitoring), App (appearance, terminal, files, servers, monitoring
/// refresh), Sessions (login devices), About + logout.
class SettingsPage extends StatefulWidget {
  const SettingsPage(
      {super.key,
      required this.session,
      required this.api,
      required this.token,
      required this.onLogout,
      this.loadProfile,
      this.loadSessions,
      this.onSessionExpired,
      required this.settings});

  final SessionInfo session;
  final NextermApi api;
  final String token;
  final VoidCallback onLogout;

  /// Called on HTTP 401 so expired sessions return to login.
  final VoidCallback? onSessionExpired;

  /// Test seams (default to live account/session endpoints).
  final AppSettings settings;

  final Future<UserInfo> Function()? loadProfile;
  final Future<List<LoginSession>> Function()? loadSessions;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  UserInfo? _profile;
  List<LoginSession>? _sessions;
  String? _error;
  String? _sessionsError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<UserInfo> _defaultProfile() async =>
      UserInfo.fromJson(await widget.api.fetchMe(widget.token));

  Future<List<LoginSession>> _defaultSessions() async {
    final raw = await widget.api.fetchLoginSessions(widget.token);
    final out = <LoginSession>[];
    for (final m in raw) {
      try {
        out.add(LoginSession.fromJson(m));
      } catch (_) {}
    }
    return out;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _sessionsError = null;
    });
    // Profile and sessions load independently: one failing endpoint
    // must not blank the whole hub.
    UserInfo? profile;
    List<LoginSession>? sessions;
    String? sessionsError;
    String? error;
    try {
      profile =
          await (widget.loadProfile?.call() ?? _defaultProfile());
    } on SessionExpiredException {
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onSessionExpired?.call();
      return;
    } catch (e) {
      error = e is NextermApiException
          ? e.message
          : 'Could not load profile.';
    }
    try {
      sessions =
          await (widget.loadSessions?.call() ?? _defaultSessions());
    } on SessionExpiredException {
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onSessionExpired?.call();
      return;
    } catch (e) {
      sessionsError = e is NextermApiException
          ? e.message
          : 'Could not load sessions.';
      sessions ??= const [];
    }
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _sessions = sessions ?? const [];
      _sessionsError = sessionsError;
      _error = profile == null ? error : null;
      _loading = false;
    });
  }

  Future<void> _revoke(LoginSession login) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke session?'),
        content: const Text(
            'This logs out that device. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.revokeLoginSession(widget.token, login.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session revoked.')),
        );
      }
      await _load();
    } on SessionExpiredException {
      widget.onSessionExpired?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e is NextermApiException
                  ? e.message
                  : 'Revoke failed.')),
        );
      }
    }
  }

  void _openIdentities() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsIdentitiesPage(
          api: widget.api,
          token: widget.token,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  void _openLinkDevice() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsLinkDevicePage(
          api: widget.api,
          token: widget.token,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  void _openApiKeys() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsApiKeysPage(
          api: widget.api,
          token: widget.token,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  void _openTotp() {
    final profile = _profile;
    if (profile == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsTotpPage(
          api: widget.api,
          token: widget.token,
          enabled: profile.totpEnabled,
          onSessionExpired: widget.onSessionExpired,
          onChanged: _load,
        ),
      ),
    );
  }

  /// Profile picture (web Account avatar equivalent). The server
  /// requires a WebP image — other formats fail with its message.
  Future<void> _changeAvatar() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Profile picture'),
        content: const Text(
            'Pick a WebP image from your device, or remove the current picture.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'remove'),
            child: const Text('Remove'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'pick'),
            child: const Text('Pick image'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'remove') {
      try {
        await widget.api.deleteAvatar(widget.token);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Picture removed.')),
        );
        await _load();
      } on SessionExpiredException {
        widget.onSessionExpired?.call();
      } on NextermApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Remove failed.')),
        );
      }
      return;
    }
    List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(type: FileType.image);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not open the file picker.')),
      );
      return;
    }
    if (picked.isEmpty || !mounted) return;
    try {
      final file = picked.first;
      final bytes = await file.readAsBytes();
      await widget.api.uploadAvatar(widget.token, bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Picture updated.')),
      );
      await _load();
    } on SessionExpiredException {
      widget.onSessionExpired?.call();
    } on NextermApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload failed.')),
      );
    }
  }

  void _openMonitoringSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsMonitoringPage(
          api: widget.api,
          token: widget.token,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  void _openAudit() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsAuditPage(
          api: widget.api,
          token: widget.token,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  Future<void> _editName() async {
    final profile = _profile;
    if (profile == null) return;
    final first = TextEditingController(text: profile.firstName ?? '');
    final last = TextEditingController(text: profile.lastName ?? '');
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Edit name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: first,
                decoration: const InputDecoration(
                    labelText: 'First name',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: last,
                decoration: const InputDecoration(
                    labelText: 'Last name',
                    border: OutlineInputBorder()),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (first.text.trim().isEmpty &&
                    last.text.trim().isEmpty) {
                  setDialog(() =>
                      error = 'Enter a first or last name.');
                  return;
                }
                try {
                  await widget.api.updateProfileName(
                    widget.token,
                    firstName: first.text.trim().isEmpty
                        ? null
                        : first.text.trim(),
                    lastName: last.text.trim().isEmpty
                        ? null
                        : last.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on SessionExpiredException {
                  widget.onSessionExpired?.call();
                } on NextermApiException catch (e) {
                  setDialog(() => error = e.message);
                } catch (_) {
                  setDialog(() => error = 'Save failed.');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    first.dispose();
    last.dispose();
    if (saved == true && mounted) _load();
  }

  Future<void> _changePassword() async {
    final pw = TextEditingController();
    final confirm = TextEditingController();
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Change password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pw,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'New password (min 3 chars)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Repeat password',
                    border: OutlineInputBorder()),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (pw.text.length < 3) {
                  setDialog(() =>
                      error = 'Password needs 3+ characters.');
                  return;
                }
                if (pw.text != confirm.text) {
                  setDialog(
                      () => error = 'Passwords do not match.');
                  return;
                }
                try {
                  await widget.api
                      .changePassword(widget.token, pw.text);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on SessionExpiredException {
                  widget.onSessionExpired?.call();
                } on NextermApiException catch (e) {
                  setDialog(() => error = e.message);
                } catch (_) {
                  setDialog(() => error = 'Save failed.');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    pw.dispose();
    confirm.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _profile == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  Text('Settings',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_error != null && _profile == null)
                    Card(
                      elevation: 0,
                      color: cs.errorContainer,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!,
                            style: TextStyle(
                                color: cs.onErrorContainer)),
                      ),
                    )
                  else if (_profile != null)
                    _ProfileCard(
                      profile: _profile!,
                      api: widget.api,
                      token: widget.token,
                      serverLabel: widget.session.label,
                    ),
                  SettingsGroup(
                    title: 'Account',
                    children: [
                      SettingsNavTile(
                        icon: Icons.person_outline,
                        title: 'Edit name',
                        subtitle: _profile == null
                            ? null
                            : '@${_profile!.username}',
                        onTap: _editName,
                      ),
                      SettingsNavTile(
                        icon: Icons.password_outlined,
                        title: 'Change password',
                        subtitle: 'Server account',
                        onTap: _changePassword,
                      ),
                      SettingsNavTile(
                        icon: Icons.photo_outlined,
                        title: 'Profile picture',
                        subtitle: 'WebP image',
                        onTap: _changeAvatar,
                      ),
                      SettingsNavTile(
                        icon: Icons.verified_user_outlined,
                        title: 'Two-factor',
                        subtitle: _profile == null
                            ? null
                            : (_profile!.totpEnabled
                                ? 'Enabled'
                                : 'Disabled'),
                        onTap: _openTotp,
                      ),
                      SettingsNavTile(
                        icon: Icons.key_outlined,
                        title: 'API keys',
                        subtitle: 'Scripts and integrations',
                        onTap: _openApiKeys,
                      ),
                      SettingsNavTile(
                        icon: Icons.link_outlined,
                        title: 'Link device',
                        subtitle: 'Authorize another device',
                        onTap: _openLinkDevice,
                      ),
                    ],
                  ),
                  SettingsGroup(
                    title: 'Server',
                    children: [
                      SettingsNavTile(
                        icon: Icons.key_outlined,
                        title: 'Identities',
                        subtitle:
                            'SSH keys and login credentials',
                        onTap: _openIdentities,
                      ),
                      SettingsNavTile(
                        icon: Icons.monitor_heart_outlined,
                        title: 'Monitoring',
                        subtitle: 'Collectors and intervals (admin)',
                        onTap: _openMonitoringSettings,
                      ),
                      SettingsNavTile(
                        icon: Icons.history_outlined,
                        title: 'Audit log',
                        subtitle: 'Who connected where (admin)',
                        onTap: _openAudit,
                      ),
                    ],
                  ),
                  AnimatedBuilder(
                    animation: widget.settings,
                    builder: (context, _) {
                      final s = widget.settings;
                      return Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                        children: [
                          SettingsGroup(
                            title: 'Appearance',
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 12, 16, 4),
                                child: LayoutBuilder(
                                  builder:
                                      (context, constraints) {
                                    final narrow = constraints
                                            .maxWidth <
                                        360;
                                    return SegmentedButton<
                                        ThemeMode>(
                                      segments: [
                                        ButtonSegment(
                                            value:
                                                ThemeMode.system,
                                            icon: narrow
                                                ? null
                                                : const Icon(Icons
                                                    .settings_suggest_outlined),
                                            label: const Text(
                                                'Auto')),
                                        ButtonSegment(
                                            value:
                                                ThemeMode.light,
                                            icon: narrow
                                                ? null
                                                : const Icon(Icons
                                                    .light_mode_outlined),
                                            label: const Text(
                                                'Light')),
                                        ButtonSegment(
                                            value:
                                                ThemeMode.dark,
                                            icon: narrow
                                                ? null
                                                : const Icon(Icons
                                                    .dark_mode_outlined),
                                            label: const Text(
                                                'Dark')),
                                      ],
                                      selected: {s.themeMode},
                                      onSelectionChanged: (sel) =>
                                          s.setThemeMode(
                                              sel.first),
                                    );
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 4, 16, 12),
                                child: Row(
                                  children: [
                                    const Text('Accent',
                                        style: TextStyle(
                                            fontWeight:
                                                FontWeight.w600)),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        alignment:
                                            WrapAlignment.end,
                                        children: [
                                          for (final seed
                                              in AppSettings
                                                  .accentChoices)
                                            Semantics(
                                              label:
                                                  'Accent color',
                                              selected: s.accentSeed ==
                                                  seed,
                                              button: true,
                                              child: Tooltip(
                                                message:
                                                    'Accent color',
                                                child:
                                                    GestureDetector(
                                                  onTap: () => s
                                                      .setAccentSeed(
                                                          seed),
                                                  child: Container(
                                                    width: 32,
                                                    height: 32,
                                                    decoration:
                                                        BoxDecoration(
                                                      color: Color(
                                                          seed),
                                                      shape: BoxShape
                                                          .circle,
                                                      border:
                                                          Border
                                                              .all(
                                                        color: s.accentSeed ==
                                                                seed
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .onSurface
                                                            : Colors
                                                                .transparent,
                                                        width:
                                                            2,
                                                      ),
                                                    ),
                                                    child: s.accentSeed ==
                                                            seed
                                                        ? Icon(
                                                            Icons
                                                                .check,
                                                            size:
                                                                18,
                                                            color: _onSeedColor(
                                                                seed),
                                                          )
                                                        : null,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SettingsGroup(
                            title: 'Terminal & files',
                            children: [
                              _SliderPrefTile(
                                icon: Icons.text_fields,
                                title: 'Terminal font size',
                                semanticLabel:
                                    'Terminal font size',
                                value: s.terminalFontSize,
                                display:
                                    '${s.terminalFontSize.round()}',
                                min: 10,
                                max: 24,
                                divisions: 14,
                                onChanged: (v) => s
                                    .setTerminalFontSize(v),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 4, 16, 12),
                                child: Row(
                                  children: [
                                    const Text('Cursor',
                                        style: TextStyle(
                                            fontWeight:
                                                FontWeight.w600)),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: LayoutBuilder(
                                        builder: (context,
                                            constraints) {
                                          final narrow =
                                              constraints
                                                      .maxWidth <
                                                  300;
                                          return SegmentedButton<
                                              String>(
                                            segments: [
                                              ButtonSegment(
                                                  value: 'block',
                                                  icon: narrow
                                                      ? null
                                                      : const Icon(
                                                          Icons
                                                              .crop_square,
                                                          size:
                                                              16),
                                                  label:
                                                      const Text(
                                                          'Block')),
                                              ButtonSegment(
                                                  value:
                                                      'underline',
                                                  icon: narrow
                                                      ? null
                                                      : const Icon(
                                                          Icons
                                                              .format_underline,
                                                          size:
                                                              16),
                                                  label:
                                                      const Text(
                                                          'Line')),
                                              ButtonSegment(
                                                  value: 'bar',
                                                  icon: narrow
                                                      ? null
                                                      : const Icon(
                                                          Icons
                                                              .height,
                                                          size:
                                                              16),
                                                  label:
                                                      const Text(
                                                          'Bar')),
                                            ],
                                            selected: {
                                              s.terminalCursor
                                            },
                                            onSelectionChanged:
                                                (sel) => s
                                                    .setTerminalCursor(
                                                        sel
                                                            .first),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SettingsSwitchTile(
                                icon: Icons.key_outlined,
                                title: 'Password fill button',
                                subtitle:
                                    'Key button in SSH sessions pastes the identity password',
                                value: s.terminalPasswordHint,
                                onChanged: (v) => s
                                    .setTerminalPasswordHint(v),
                              ),
                              SettingsSwitchTile(
                                icon: Icons.visibility_off_outlined,
                                title: 'Show hidden files',
                                subtitle:
                                    'List dotfiles in the SFTP browser',
                                value: s.sftpShowHidden,
                                onChanged: (v) =>
                                    s.setSftpShowHidden(v),
                              ),
                              SettingsSwitchTile(
                                icon: Icons.delete_outline,
                                title: 'Confirm delete',
                                subtitle:
                                    'Ask before deleting remote files',
                                value: s.sftpConfirmDelete,
                                onChanged: (v) => s
                                    .setSftpConfirmDelete(v),
                              ),
                            ],
                          ),
                          SettingsGroup(
                            title: 'Lists & monitoring',
                            children: [
                              SettingsSwitchTile(
                                icon: Icons.grid_view_outlined,
                                title: 'Grid by default',
                                subtitle:
                                    'Open Servers as grid instead of list',
                                value: s.serversGridDefault,
                                onChanged: (v) => s
                                    .setServersGridDefault(v),
                              ),
                              SettingsSwitchTile(
                                icon: Icons.autorenew,
                                title: 'Auto-refresh monitoring',
                                subtitle:
                                    'Reload the monitoring list on an interval',
                                value: s.monitoringAutoRefresh,
                                onChanged: (v) => s
                                    .setMonitoringAutoRefresh(v),
                              ),
                              _SliderPrefTile(
                                icon: Icons.timer_outlined,
                                title: 'Refresh interval',
                                semanticLabel:
                                    'Monitoring refresh interval in seconds',
                                value: s.monitoringIntervalSec
                                    .toDouble(),
                                display:
                                    '${s.monitoringIntervalSec}s',
                                min: 15,
                                max: 300,
                                divisions: 19,
                                enabled: s.monitoringAutoRefresh,
                                disabledHint:
                                    'Enable auto-refresh to change the interval.',
                                onChanged: (v) => s.setMonitoringInterval(
                                    v.round()),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                    child: Text('Login sessions',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (_sessionsError != null)
                    Padding(
                      padding:
                          const EdgeInsets.only(bottom: 8),
                      child: Text(_sessionsError!,
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.error)),
                    ),
                  if ((_sessions ?? const []).isEmpty)
                    Text('No other sessions.',
                        style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant))
                  else
                    for (final login in _sessions!)
                      Card(
                        elevation: 0,
                        color: cs.surfaceContainerHigh,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(16)),
                        child: ListTile(
                          leading: const Icon(Icons.smartphone),
                          title: Text(login.userAgent ?? 'Session',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            [
                              if (login.ip != null) login.ip!,
                              if (login.lastActivity != null)
                                _shortDate(login.lastActivity!),
                            ].join(' • '),
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant),
                          ),
                          trailing: TextButton(
                            onPressed: () => _revoke(login),
                            child: const Text('Revoke'),
                          ),
                        ),
                      ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    color: cs.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.logout,
                            color: cs.onErrorContainer, size: 20),
                      ),
                      title: const Text('Log out',
                          style:
                              TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text(
                          'Delete the session on this device',
                          style: TextStyle(fontSize: 12)),
                      onTap: () => _confirmLogout(context),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Nexterm V2 · ${widget.session.label}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.outline),
                      textAlign: TextAlign.center),
                ],
              ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
            'This deletes the session on this device. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onLogout();
  }
}

/// Check color readable on an accent seed (white on dark seeds).
Color _onSeedColor(int seed) {
  final c = Color(seed);
  final luminance =
      0.299 * (c.r * 255) + 0.587 * (c.g * 255) + 0.114 * (c.b * 255);
  return luminance > 150 ? Colors.black : Colors.white;
}

String _shortDate(DateTime dt) {  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  String two(int v) => v.toString().padLeft(2, '0');
  final month =
      dt.month >= 1 && dt.month <= 12 ? months[dt.month - 1] : '?';
  return '${two(dt.day)} $month, ${two(dt.hour)}:${two(dt.minute)}';
}

/// Full-width slider row for an app preference: icon + title + value
/// on top, 48px slider below (usable touch target + semantics).
class _SliderPrefTile extends StatelessWidget {
  const _SliderPrefTile(
      {required this.icon,
      required this.title,
      required this.semanticLabel,
      required this.value,
      required this.display,
      required this.min,
      required this.max,
      required this.divisions,
      required this.onChanged,
      this.enabled = true,
      this.disabledHint});

  final IconData icon;
  final String title;
  final String semanticLabel;
  final double value;
  final String display;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final String? disabledHint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    color: cs.onPrimaryContainer, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600)),
              ),
              Text(display,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700)),
            ],
          ),
          Semantics(
            slider: true,
            label: semanticLabel,
            value: display,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: display,
              onChanged: enabled ? onChanged : null,
            ),
          ),
          if (!enabled && disabledHint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(disabledHint!,
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard(
      {required this.profile,
      required this.api,
      required this.token,
      required this.serverLabel});

  final UserInfo profile;
  final NextermApi api;
  final String token;
  final String serverLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHigh,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ClipOval(
              child: Image.network(
                profile.avatarUrl(api.baseUrl, token),
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 52,
                  height: 52,
                  color: cs.primaryContainer,
                  child: Icon(Icons.person,
                      color: cs.onPrimaryContainer),
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
                      Expanded(
                        child: Text(profile.displayName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16)),
                      ),
                      if (profile.isAdmin)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Admin',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onPrimaryContainer)),
                        ),
                    ],
                  ),
                  Text(serverLabel,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
