import 'package:flutter/material.dart';

import '../../../services/account_service.dart';
import '../../../utils/api_exception.dart';
import '../../../utils/app_icons.dart';
import '../../../utils/auth_manager.dart';
import '../../../widgets/app_ui.dart';
import '../ui.dart';

String _ago(DateTime? date) {
  if (date == null) return 'never';
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  if (diff.inDays < 30) return '${diff.inDays} d ago';
  final l = date.toLocal();
  return '${l.day}.${l.month}.${l.year}';
}

// --- Monitoring settings -----------------------------------------------------

/// Global monitoring settings (web: Settings → Monitoring).
class MonitoringSettingsPage extends StatefulWidget {
  final AuthManager authManager;

  const MonitoringSettingsPage({super.key, required this.authManager});

  @override
  State<MonitoringSettingsPage> createState() => _MonitoringSettingsPageState();
}

class _MonitoringSettingsPageState extends State<MonitoringSettingsPage> {
  MonitoringSettings? _settings;
  MonitoringSettings? _saved;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String? get _token => widget.authManager.sessionToken;
  bool get _dirty =>
      _settings != null &&
      _saved != null &&
      _settings!.toJson().toString() != _saved!.toJson().toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null) return;
    try {
      final s = await AccountService.getMonitoringSettings(token);
      if (!mounted) return;
      setState(() {
        _settings = s;
        _saved = s;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(
          e,
          fallback: 'Could not load monitoring settings.',
        );
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final token = _token;
    final settings = _settings;
    if (token == null || settings == null) return;
    setState(() => _saving = true);
    try {
      await AccountService.saveMonitoringSettings(token, settings);
      if (!mounted) return;
      setState(() => _saved = settings);
      settingsToast(context, 'Monitoring settings saved.');
    } catch (e) {
      if (mounted) {
        settingsToast(
          context,
          friendlyApiError(e, fallback: 'Could not save the settings.'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _slider({
    required String title,
    required String unit,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
    int step = 1,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 14.5)),
              ),
              Text(
                '$value $unit',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: ((max - min) / step).round(),
            label: '$value $unit',
            onChanged: (v) => onChanged(((v / step).round()) * step),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return SettingsPage(
      title: 'Monitoring',
      subtitle: 'Global status checks and metrics',
      onRefresh: _load,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (s == null)
          SizedBox(
            height: 360,
            child: AppErrorState(
              message: _error ?? 'Could not load monitoring settings.',
              onRetry: _load,
            ),
          )
        else ...[
          SettingsGroup(
            title: 'Status checker',
            footer: 'Checks whether servers are reachable.',
            children: [
              SettingsSwitchTile(
                icon: AppIcons.checkCircle,
                title: 'Enable status checker',
                value: s.statusCheckerEnabled,
                onChanged: (v) => setState(
                  () => _settings = s.copyWith(statusCheckerEnabled: v),
                ),
              ),
              _slider(
                title: 'Check interval',
                unit: 's',
                value: s.statusInterval,
                min: 10,
                max: 300,
                step: 5,
                onChanged: (v) =>
                    setState(() => _settings = s.copyWith(statusInterval: v)),
              ),
            ],
          ),
          SettingsGroup(
            title: 'Metrics',
            footer: 'CPU, memory, disks, network and processes of servers.',
            children: [
              SettingsSwitchTile(
                icon: AppIcons.chartBox,
                title: 'Enable monitoring',
                value: s.monitoringEnabled,
                onChanged: (v) => setState(
                  () => _settings = s.copyWith(monitoringEnabled: v),
                ),
              ),
              _slider(
                title: 'Collection interval',
                unit: 's',
                value: s.monitoringInterval,
                min: 30,
                max: 600,
                step: 10,
                onChanged: (v) => setState(
                  () => _settings = s.copyWith(monitoringInterval: v),
                ),
              ),
              _slider(
                title: 'Keep data for',
                unit: 'h',
                value: s.dataRetentionHours,
                min: 1,
                max: 24,
                onChanged: (v) => setState(
                  () => _settings = s.copyWith(dataRetentionHours: v),
                ),
              ),
            ],
          ),
          SettingsGroup(
            title: 'Performance',
            children: [
              _slider(
                title: 'Connection timeout',
                unit: 's',
                value: s.connectionTimeout,
                min: 5,
                max: 120,
                step: 5,
                onChanged: (v) => setState(
                  () => _settings = s.copyWith(connectionTimeout: v),
                ),
              ),
              _slider(
                title: 'Servers per batch',
                unit: '',
                value: s.batchSize,
                min: 1,
                max: 50,
                onChanged: (v) =>
                    setState(() => _settings = s.copyWith(batchSize: v)),
              ),
            ],
          ),
          SettingsButton(
            label: 'Save changes',
            busy: _saving,
            onPressed: _dirty ? _save : null,
          ),
        ],
      ],
    );
  }
}

// --- Engines -----------------------------------------------------------------

/// Connection engines and their live status (web: Settings → Engines).
class EnginesPage extends StatefulWidget {
  final AuthManager authManager;

  const EnginesPage({super.key, required this.authManager});

  @override
  State<EnginesPage> createState() => _EnginesPageState();
}

class _EnginesPageState extends State<EnginesPage> {
  List<EngineInfoItem>? _engines;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    try {
      final engines = await AccountService.listEngines(token);
      if (!mounted) return;
      setState(() {
        _engines = engines;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(e, fallback: 'Could not load engines.');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final engines = _engines;
    return SettingsPage(
      title: 'Engines',
      subtitle: 'Where connections are made from',
      onRefresh: _load,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (engines == null)
          SizedBox(
            height: 360,
            child: AppErrorState(
              message: _error ?? 'Could not load engines.',
              onRetry: _load,
            ),
          )
        else if (engines.isEmpty)
          const SizedBox(
            height: 360,
            child: AppEmptyState(
              icon: AppIcons.dns,
              title: 'No engines',
              message: 'Engines are managed in the web client.',
            ),
          )
        else ...[
          for (final e in engines)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AppIconBox(
                          icon: AppIcons.dns,
                          size: 40,
                          background: e.connected
                              ? cs.primaryContainer
                              : cs.errorContainer,
                          foreground: e.connected
                              ? cs.onPrimaryContainer
                              : cs.onErrorContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                e.isLocal ? 'Local engine' : 'Remote engine',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SettingsPill(
                          e.connected ? 'Online' : 'Offline',
                          color: e.connected
                              ? const Color(0xFF4CAF50)
                              : cs.error,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (e.version != null) SettingsPill('v${e.version}'),
                        if (e.remoteAddr != null) SettingsPill(e.remoteAddr!),
                        if (e.connected)
                          SettingsPill(
                            e.encrypted ? 'Encrypted' : 'Unencrypted',
                            color: e.encrypted
                                ? const Color(0xFF4CAF50)
                                : Colors.orange,
                          ),
                        if (!e.connected)
                          SettingsPill('Last seen ${_ago(e.lastConnectedAt)}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// --- Users -------------------------------------------------------------------

/// Read-only list of user accounts (web: Settings → Users).
class UsersPage extends StatefulWidget {
  final AuthManager authManager;

  const UsersPage({super.key, required this.authManager});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<UserInfoItem>? _users;
  int _total = 0;
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    try {
      final result = await AccountService.listUsers(
        token,
        search: _query.trim(),
      );
      if (!mounted) return;
      setState(() {
        _users = result.users;
        _total = result.total;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(e, fallback: 'Could not load users.');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final users = _users;
    return SettingsPage(
      title: 'Users',
      subtitle: users == null
          ? null
          : '$_total ${_total == 1 ? 'user' : 'users'}',
      onRefresh: _load,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (users == null)
          SizedBox(
            height: 360,
            child: AppErrorState(
              message: _error ?? 'Could not load users.',
              onRetry: _load,
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              onChanged: (v) {
                _query = v;
                _load();
              },
              decoration: settingsInputDecoration(
                context,
                hint: 'Search users…',
              ).copyWith(prefixIcon: const Icon(AppIcons.magnify, size: 20)),
            ),
          ),
          if (users.isEmpty)
            const SizedBox(
              height: 200,
              child: AppEmptyState(
                icon: AppIcons.account,
                title: 'No users found',
              ),
            ),
          for (final u in users)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: Row(
                  children: [
                    const AppIconBox(icon: AppIcons.account, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            u.displayName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '@${u.username}',
                            style: TextStyle(fontSize: 12, color: cs.outline),
                          ),
                          if (u.groups.isNotEmpty || u.totpEnabled)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final g in u.groups) SettingsPill(g),
                                  if (u.totpEnabled)
                                    const SettingsPill(
                                      '2FA',
                                      color: Color(0xFF4CAF50),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
