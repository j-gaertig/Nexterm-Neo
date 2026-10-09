import 'package:flutter/material.dart';

import '../../servers/server_models.dart';
import 'server_detail_sheet.dart';

/// Servers list page (tap → sessions sheet, long-press → actions sheet).
class ServersPage extends StatelessWidget {
  const ServersPage({super.key});

  // TODO: replace demo data with GET /api/entries/list.
  List<ServerEntry> get _servers => demoServers;

  void _openSessionsSheet(BuildContext context, ServerEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
      child: servers.isEmpty
          ? const Center(child: Text('No servers yet.'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: servers.length,
              itemBuilder: (context, index) {
                final entry = servers[index];
                return _ServerTile(
                  entry: entry,
                  onTap: () => _openSessionsSheet(context, entry),
                  onLongPress: () => _openActionsSheet(context, entry),
                );
              },
            ),
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
          '${entry.address} • ${(entry.protocol ?? 'ssh').toUpperCase()}',
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
