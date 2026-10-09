import 'package:flutter/material.dart';

import '../../servers/server_models.dart';
import 'servers_page.dart' show protocolIcon;

/// Bottom sheet for a server: active sessions + new session,
/// or quick actions on long-press. UI only — no backend calls yet.
class ServerDetailSheet extends StatelessWidget {
  const ServerDetailSheet.sessions(
      {super.key, required this.entry, this.sessions = const []})
      : _mode = _SheetMode.sessions;

  const ServerDetailSheet.actions({super.key, required this.entry})
      : sessions = const [],
        _mode = _SheetMode.actions;

  final ServerEntry entry;

  /// Active sessions of this server (empty until connections are wired).
  final List<ServerSessionInfo> sessions;
  final _SheetMode _mode;

  // TODO: wire GET /api/connections for this server.

  static const double _rowHeight = 68;

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _DragHandle(),
              const SizedBox(height: 12),
              _Header(entry: entry),
              const SizedBox(height: 16),
              if (_mode == _SheetMode.sessions) ...[
                _SessionsSection(
                  sessions: sessions,
                  onCloseAll: () => _comingSoon(context),
                  onCloseSession: (_) => _comingSoon(context),
                ),
                const SizedBox(height: 16),
                _NewSessionSection(
                  entry: entry,
                  onStart: (_) => _comingSoon(context),
                ),
              ] else
                _ActionsSection(
                  onAction: (_) => _comingSoon(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SheetMode { sessions, actions }

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.entry});

  final ServerEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(protocolIcon(entry.protocol),
              color: cs.onPrimaryContainer, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name,
                  style: tt.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(
                formatServerSubtitle(entry),
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SessionsSection extends StatelessWidget {
  const _SessionsSection(
      {required this.sessions,
      required this.onCloseAll,
      required this.onCloseSession});

  final List<ServerSessionInfo> sessions;
  final VoidCallback onCloseAll;
  final ValueChanged<ServerSessionInfo> onCloseSession;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // Cap the list at ~2.5 rows, scroll within.
    final visible =
        sessions.length > 2 ? 2.5 : sessions.length.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Active sessions (${sessions.length})',
                style: tt.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton(
              onPressed: sessions.isEmpty ? null : onCloseAll,
              child: const Text('Close all'),
            ),
          ],
        ),
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No active sessions.',
                style: TextStyle(fontSize: 13, color: cs.outline)),
          )
        else
          Container(
            height: visible * ServerDetailSheet._rowHeight,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: sessions.length,
              separatorBuilder: (_, _) => Divider(
                  height: 1,
                  indent: 56,
                  color: cs.outlineVariant.withValues(alpha: 0.4)),
              itemBuilder: (context, index) {
                final session = sessions[index];
                return SizedBox(
                  height: ServerDetailSheet._rowHeight,
                  child: _SessionRow(
                    session: session,
                    onClose: () => onCloseSession(session),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.onClose});

  final ServerSessionInfo session;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(protocolIcon(session.kind),
                color: cs.onPrimaryContainer, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(session.kind.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                Text('Opened ${formatOpenedAt(session.openedAt)}',
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close session',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _NewSessionSection extends StatelessWidget {
  const _NewSessionSection({required this.entry, required this.onStart});

  final ServerEntry entry;
  final ValueChanged<String> onStart;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final primary =
        entry.primaryProtocol == 'rdp' ? 'RDP' : 'SSH';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('New session',
            style:
                tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => onStart(primary.toLowerCase()),
                icon: Icon(primary == 'RDP'
                    ? Icons.monitor
                    : Icons.terminal),
                label: Text(primary),
                style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onStart('sftp'),
                icon: const Icon(Icons.folder),
                label: const Text('SFTP'),
                style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionsSection extends StatelessWidget {
  const _ActionsSection({required this.onAction});

  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _actionTile(context, Icons.bolt, 'Quick connect', 'quick-connect',
            destructive: false),
        _actionTile(context, Icons.power_settings_new, 'Wake on LAN',
            'wake-on-lan',
            destructive: false),
        _actionTile(context, Icons.content_copy, 'Duplicate', 'duplicate',
            destructive: false),
        _actionTile(context, Icons.edit, 'Edit', 'edit',
            destructive: false),
        _actionTile(context, Icons.delete, 'Delete', 'delete',
            destructive: true),
        const SizedBox(height: 4),
        Text('More actions follow in later steps.',
            style: TextStyle(fontSize: 12, color: cs.outline)),
      ],
    );
  }

  Widget _actionTile(BuildContext context, IconData icon, String title,
      String action,
      {required bool destructive}) {
    final cs = Theme.of(context).colorScheme;
    final color = destructive ? cs.error : cs.onSurface;
    return ListTile(
      leading: Icon(icon, color: destructive ? cs.error : cs.primary),
      title: Text(title,
          style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      onTap: () {
        // Snackbar first: this context is deactivated after pop.
        onAction(action);
        Navigator.pop(context);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}
