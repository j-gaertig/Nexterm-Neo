import 'package:flutter/material.dart';

import '../../api/nexterm_api.dart';

/// Read-only audit trail (`GET /api/audit/logs`, needs `AUDIT_VIEW`).
/// Web Audit page equivalent, latest-first, 50 rows per load.
class SettingsAuditPage extends StatefulWidget {
  const SettingsAuditPage(
      {super.key,
      required this.api,
      required this.token,
      this.onSessionExpired});

  final NextermApi api;
  final String token;
  final VoidCallback? onSessionExpired;

  @override
  State<SettingsAuditPage> createState() => _SettingsAuditPageState();
}

class _SettingsAuditPageState extends State<SettingsAuditPage> {
  List<Map<String, dynamic>> _logs = [];
  int _total = 0;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;

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
          await widget.api.fetchAuditLogs(widget.token);
      if (!mounted) return;
      setState(() {
        _logs = _asList(data['logs']);
        _total = (data['total'] as num?)?.toInt() ?? _logs.length;
        _loading = false;
      });
    } on SessionExpiredException {
      if (!mounted) return;
      setState(() => _loading = false);
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
        _error = 'Could not load audit logs.';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final data = await widget.api.fetchAuditLogs(widget.token,
          offset: _logs.length);
      if (!mounted) return;
      setState(() {
        _logs = [..._logs, ..._asList(data['logs'])];
        _total = (data['total'] as num?)?.toInt() ?? _total;
        _loadingMore = false;
      });
    } on SessionExpiredException {
      if (mounted) setState(() => _loadingMore = false);
      widget.onSessionExpired?.call();
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  static List<Map<String, dynamic>> _asList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
          title: Text('Audit log ($_total)')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null && _logs.isEmpty
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
                : _logs.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(32),
                        children: const [
                          SizedBox(height: 64),
                          Text('No audit entries.',
                              textAlign: TextAlign.center),
                        ],
                      )
                    : ListView.builder(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                            16, 8, 16, 96),
                        itemCount: _logs.length +
                            (_logs.length < _total ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= _logs.length) {
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(
                                      vertical: 16),
                              child: Center(
                                child: _loadingMore
                                    ? const CircularProgressIndicator()
                                    : TextButton(
                                        onPressed:
                                            _loadMore,
                                        child: const Text(
                                            'Load more'),
                                      ),
                              ),
                            );
                          }
                          final log = _logs[i];
                          final date = _shortDate(
                              '${log['timestamp'] ?? log['createdAt'] ?? ''}');
                          final parts = <String>[
                            if (log['resource'] != null)
                              '${log['resource']}',
                            if (log['ipAddress'] != null)
                              '${log['ipAddress']}',
                            if (date.isNotEmpty) date,
                          ];
                          return Card(
                            elevation: 0,
                            color: cs.surfaceContainerHigh,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                        16)),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                  '${log['action'] ?? '—'}',
                                  style: const TextStyle(
                                      fontWeight:
                                          FontWeight.w600,
                                      fontSize: 14)),
                              subtitle: Text(
                                parts.join(' • '),
                                style: const TextStyle(
                                    fontSize: 12),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

String _shortDate(String raw) {
  final dt = DateTime.tryParse(raw)?.toLocal();
  if (dt == null) return raw.isEmpty ? '' : raw;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}
