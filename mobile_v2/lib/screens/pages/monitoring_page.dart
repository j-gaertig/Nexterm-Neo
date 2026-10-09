import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/nexterm_api.dart';
import '../../monitoring/monitoring_models.dart';
import '../../monitoring/monitoring_repository.dart';
import 'monitoring_detail_page.dart';

/// Monitoring overview: one card per monitored server (mirrors the web
/// grid). Tap a card for the extended detail view.
class MonitoringPage extends StatefulWidget {
  const MonitoringPage(
      {super.key,
      required this.repository,
      this.onSessionExpired,
      this.autoRefresh = true,
      this.refreshInterval = const Duration(seconds: 30)});

  final MonitoringRepository repository;

  /// Called on HTTP 401 so expired sessions return to login.
  final VoidCallback? onSessionExpired;

  /// Reload automatically on an interval (device preference).
  final bool autoRefresh;
  final Duration refreshInterval;

  @override
  State<MonitoringPage> createState() => _MonitoringPageState();
}

class _MonitoringPageState extends State<MonitoringPage> {
  final _searchController = TextEditingController();
  Timer? _refreshTimer;
  String _query = '';
  List<MonitoredServer>? _servers;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _startRefreshTimer();
  }

  @override
  void didUpdateWidget(MonitoringPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // App prefs (interval/toggle) arrive as constructor params —
    // restart the timer so changes apply without an app restart.
    if (oldWidget.autoRefresh != widget.autoRefresh ||
        oldWidget.refreshInterval != widget.refreshInterval) {
      _startRefreshTimer();
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (widget.autoRefresh) {
      _refreshTimer = Timer.periodic(
          widget.refreshInterval, (_) => _load(silent: true));
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final servers = await widget.repository.fetchServers();
      if (!mounted) return;
      setState(() {
        _servers = servers;
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
        _error = 'Could not load monitoring data.';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _openDetail(MonitoredServer server) {
    if (!server.isOnline) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MonitoringDetailPage(
            server: server,
            repository: widget.repository,
            onSessionExpired: widget.onSessionExpired),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final all = _servers ?? const <MonitoredServer>[];
    final servers = q.isEmpty
        ? all
        : all
            .where((s) =>
                s.name.toLowerCase().contains(q) ||
                s.ip.toLowerCase().contains(q))
            .toList();
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search servers',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading && _servers == null
                  ? ListView(
                      physics:
                          const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : _error != null && _servers == null
                      ? ListView(
                          physics:
                              const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(32),
                          children: [
                            const SizedBox(height: 64),
                            Text(_error!,
                                textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton(
                                onPressed: _load,
                                child: const Text('Retry')),
                          ],
                        )
                      : servers.isEmpty
                          ? ListView(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(32),
                              children: [
                                Center(
                                  child: Text(
                                    _query.isEmpty
                                        ? 'No monitored servers.'
                                        : 'No servers match "$_query".',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 96),
                              itemCount: servers.length,
                              itemBuilder: (context, index) {
                                final server = servers[index];
                                return _MonitorCard(
                                  server: server,
                                  onTap: () => _openDetail(server),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonitorCard extends StatelessWidget {
  const _MonitorCard({required this.server, required this.onTap});

  final MonitoredServer server;
  final VoidCallback onTap;

  Color _statusColor(ColorScheme cs) {
    switch (server.status) {
      case 'online':
        return Colors.green;
      case 'offline':
        return cs.error;
      case 'error':
        return Colors.orange;
      default:
        return cs.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: server.isOnline ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusDot(color: _statusColor(cs)),
                  const SizedBox(width: 8),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.dns,
                        color: cs.onPrimaryContainer, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(server.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                        Text(server.address,
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  if (server.isOnline)
                    Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 12),
              if (server.isOnline) ...[
                Row(
                  children: [
                    _metric(context, 'CPU',
                        server.cpu != null ? '${server.cpu!.toStringAsFixed(1)}%' : 'N/A'),
                    _metric(context, 'Memory',
                        server.mem != null ? '${server.mem!.toStringAsFixed(1)}%' : 'N/A'),
                    _metric(context, 'Load',
                        server.load != null ? server.load!.toStringAsFixed(2) : 'N/A'),
                    _metric(context, 'Processes',
                        server.processes?.toString() ?? 'N/A'),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Uptime: ${formatUptime(server.uptimeSeconds)}',
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ] else ...[
                Row(
                  children: [
                    Icon(
                        server.status == 'error'
                            ? Icons.error_outline
                            : Icons.cloud_off,
                        size: 18,
                        color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        server.status == 'error'
                            ? 'Connection error'
                            : server.status == 'offline'
                                ? 'Server offline'
                                : 'Status unknown',
                        style: TextStyle(
                            fontSize: 13, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                if (server.lastSeen != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 26),
                    child: Text(
                      'Last seen ${formatOpenedAtShort(server.lastSeen!)}',
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

String formatOpenedAtShort(DateTime dt) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.day)}.${two(dt.month)}. ${two(dt.hour)}:${two(dt.minute)}';
}
