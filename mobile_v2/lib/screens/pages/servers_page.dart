import 'package:flutter/material.dart';

import '../../api/nexterm_api.dart';
import '../../servers/server_models.dart';
import '../../servers/server_repository.dart';
import 'server_detail_sheet.dart';

/// Servers list page: real data via [ServerRepository]
/// (tap → sessions sheet, long-press → actions sheet).
class ServersPage extends StatefulWidget {
  const ServersPage(
      {super.key, required this.repository, required this.onSessionExpired});

  final ServerRepository repository;
  final VoidCallback onSessionExpired;

  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  List<ServerEntry>? _servers;
  String? _error;
  bool _loading = true;

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
      final servers = await widget.repository.fetchServers();
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _loading = false;
      });
    } on SessionExpiredException {
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onSessionExpired();
    } on NextermApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load servers.';
        _loading = false;
      });
    }
  }

  void _openSessionsSheet(BuildContext context, ServerEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // TODO: wire GET /api/connections for this server.
      builder: (_) => ServerDetailSheet.sessions(entry: entry),
    );
  }

  void _openActionsSheet(BuildContext context, ServerEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ServerDetailSheet.actions(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final servers = _servers;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: _loading && servers == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null && servers == null
                ? _ErrorView(message: _error!, onRetry: _load)
                : servers == null || servers.isEmpty
                    ? _EmptyView(onRefresh: _load)
                    : ListView.builder(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        padding:
                            const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        itemCount: servers.length,
                        itemBuilder: (context, index) {
                          final entry = servers[index];
                          return _ServerTile(
                            entry: entry,
                            onTap: () =>
                                _openSessionsSheet(context, entry),
                            onLongPress: () =>
                                _openActionsSheet(context, entry),
                          );
                        },
                      ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 64),
        Icon(Icons.cloud_off, size: 56, color: cs.onSurfaceVariant),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 64),
        Icon(Icons.dns, size: 56, color: cs.onSurfaceVariant),
        const SizedBox(height: 16),
        const Text('No servers yet.', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        OutlinedButton(
            onPressed: onRefresh, child: const Text('Refresh')),
      ],
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile(
      {required this.entry, required this.onTap, required this.onLongPress});

  final ServerEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(protocolIcon(entry.protocol),
              color: cs.onPrimaryContainer, size: 20),
        ),
        title: Text(entry.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          formatServerSubtitle(entry),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing:
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        onTap: onTap,
        onLongPress: onLongPress,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}

/// Icon for a connection protocol (shared with the detail sheet).
IconData protocolIcon(String? protocol) {
  switch ((protocol ?? '').toLowerCase()) {
    case 'rdp':
      return Icons.monitor;
    case 'sftp':
    case 'ftp':
    case 'ftps':
      return Icons.folder;
    case 'vnc':
      return Icons.desktop_windows;
    default:
      return Icons.terminal;
  }
}
