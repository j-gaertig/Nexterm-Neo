import 'package:flutter/material.dart';

import '../../api/nexterm_api.dart';
import '../../settings/settings_widgets.dart';

/// Server-side monitoring settings (`GET/PATCH
/// /api/monitoring/settings/global`). Admin only — 403 surfaces as
/// a permission message instead of a dead end.
class SettingsMonitoringPage extends StatefulWidget {
  const SettingsMonitoringPage(
      {super.key,
      required this.api,
      required this.token,
      this.onSessionExpired,
      this.loader});

  final NextermApi api;
  final String token;
  final VoidCallback? onSessionExpired;

  /// Test seam (defaults to live endpoint).
  final Future<Map<String, dynamic>> Function()? loader;

  @override
  State<SettingsMonitoringPage> createState() =>
      _SettingsMonitoringPageState();
}

class _SettingsMonitoringPageState extends State<SettingsMonitoringPage> {
  Map<String, dynamic>? _settings;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data =
          await (widget.loader?.call() ??
              widget.api.fetchMonitoringGlobalSettings(widget.token));
      if (!mounted) return;
      setState(() {
        _settings = Map<String, dynamic>.from(data);
        _loading = false;
      });
    } on SessionExpiredException {
      if (!mounted) return;
      widget.onSessionExpired?.call();
      return;
    } on NextermApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load monitoring settings.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final current = _settings;
    if (current == null || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.api.updateMonitoringGlobalSettings(
          widget.token, current);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Monitoring settings saved.')),
      );
    } on SessionExpiredException {
      widget.onSessionExpired?.call();
    } on NextermApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save failed.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _set(String key, Object? value) {
    setState(() {
      _settings = {...?_settings, key: value};
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoring'),
        actions: [
          if (_settings != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _saving
                  ? const Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2)))
                  : FilledButton.tonal(
                      onPressed: _save,
                      child: const Text('Save'),
                    ),
            ),
        ],
      ),
      body: _loading
          ? const SettingsStateView.loading()
          : _error != null && _settings == null
              ? SettingsStateView.error(
                  message: _error!, onRetry: _load)
              : SingleChildScrollView(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(
                    children: [
                      SettingsGroup(
                        title: 'Collectors',
                        children: [
                          SettingsSwitchTile(
                            icon: Icons.monitor_heart_outlined,
                            title: 'Status checker',
                            subtitle:
                                'Probe reachability on an interval',
                            value: _settings!['statusCheckerEnabled'] !=
                                false,
                            onChanged: (v) =>
                                _set('statusCheckerEnabled', v),
                          ),
                          SettingsSwitchTile(
                            icon: Icons.show_chart,
                            title: 'Metrics collection',
                            subtitle:
                                'CPU, memory, disk and network history',
                            value:
                                _settings!['monitoringEnabled'] !=
                                    false,
                            onChanged: (v) =>
                                _set('monitoringEnabled', v),
                          ),
                        ],
                      ),
                      SettingsGroup(
                        title: 'Intervals & limits',
                        children: [
                          _NumberTile(
                            icon: Icons.timer_outlined,
                            title: 'Status interval',
                            subtitle: 'Seconds between probes (10–300)',
                            value: (_settings!['statusInterval']
                                        as num?)
                                    ?.toInt() ??
                                60,
                            min: 10,
                            max: 300,
                            onChanged: (v) =>
                                _set('statusInterval', v),
                          ),
                          _NumberTile(
                            icon: Icons.stacked_line_chart,
                            title: 'Metrics interval',
                            subtitle:
                                'Seconds between samples (30–600)',
                            value: (_settings!['monitoringInterval']
                                        as num?)
                                    ?.toInt() ??
                                60,
                            min: 30,
                            max: 600,
                            onChanged: (v) => _set(
                                'monitoringInterval', v),
                          ),
                          _NumberTile(
                            icon: Icons.history,
                            title: 'Retention',
                            subtitle: 'Hours of history kept (1–24)',
                            value: (_settings!['dataRetentionHours']
                                        as num?)
                                    ?.toInt() ??
                                6,
                            min: 1,
                            max: 24,
                            onChanged: (v) => _set(
                                'dataRetentionHours', v),
                          ),
                          _NumberTile(
                            icon: Icons.hourglass_bottom,
                            title: 'Connection timeout',
                            subtitle:
                                'Seconds before a probe gives up (5–120)',
                            value: (_settings!['connectionTimeout']
                                        as num?)
                                    ?.toInt() ??
                                10,
                            min: 5,
                            max: 120,
                            onChanged: (v) => _set(
                                'connectionTimeout', v),
                          ),
                          _NumberTile(
                            icon: Icons.batch_prediction_outlined,
                            title: 'Batch size',
                            subtitle:
                                'Servers per collection batch (1–50)',
                            value: (_settings!['batchSize']
                                        as num?)
                                    ?.toInt() ??
                                10,
                            min: 1,
                            max: 50,
                            onChanged: (v) =>
                                _set('batchSize', v),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }
}

/// Stepper row for an integer server setting.
class _NumberTile extends StatelessWidget {
  const _NumberTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.value,
      required this.min,
      required this.max,
      required this.onChanged});

  final IconData icon;
  final String title;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.max,
            children: [
              IconButton(
                tooltip: 'Decrease $title',
                icon: const Icon(Icons.remove),
                onPressed: value > min
                    ? () => onChanged(value - 1)
                    : null,
              ),
              SizedBox(
                width: 48,
                child: Text('$value',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'Increase $title',
                icon: const Icon(Icons.add),
                onPressed: value < max
                    ? () => onChanged(value + 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
