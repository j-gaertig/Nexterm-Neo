import 'package:flutter/material.dart';

import '../../remote/session_opener.dart';
import '../../servers/identity.dart';
import '../../servers/server_models.dart';
import '../../servers/tag_models.dart';
import 'servers_page.dart' show protocolIcon;

/// Bottom sheet for a server: active sessions + new session,
/// or quick actions on long-press.
class ServerDetailSheet extends StatelessWidget {
  const ServerDetailSheet.sessions({
    super.key,
    required this.entry,
    this.sessions = const [],
    this.onStartSession,
    this.onOpenSession,
    this.onCloseSession,
    this.onCloseAll,
    this.onAction,
  }) : _mode = _SheetMode.sessions;

  const ServerDetailSheet.actions(
      {super.key, required this.entry, this.onAction})
      : sessions = const [],
        onStartSession = null,
        onOpenSession = null,
        onCloseSession = null,
        onCloseAll = null,
        _mode = _SheetMode.actions;

  final ServerEntry entry;

  /// Active sessions of this server.
  final List<ConnectionInfo> sessions;

  /// Start a new session of this kind (null = placeholder snackbar).
  final ValueChanged<SessionKind>? onStartSession;

  /// Reopen an existing session in its viewer.
  final ValueChanged<ConnectionInfo>? onOpenSession;

  /// Close one session.
  final ValueChanged<ConnectionInfo>? onCloseSession;

  /// Close all sessions of this server.
  final VoidCallback? onCloseAll;

  /// Quick action id (quick-connect, run-script, browser, wake-on-lan,
  /// move, tags, notes, duplicate, edit, delete) — null = placeholder snackbar.
  final ValueChanged<String>? onAction;
  final _SheetMode _mode;

  static const double _rowHeight = 68;

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
                  onCloseAll: onCloseAll ?? () {},
                  onCloseSession: onCloseSession ?? (_) {},
                  onOpenSession: onOpenSession ?? (_) {},
                ),
                const SizedBox(height: 16),
                _NewSessionSection(
                  entry: entry,
                  onStart: onStartSession ?? (_) {},
                ),
              ] else
                _ActionsSection(
                  entry: entry,
                  onAction: onAction ?? (_) {},
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
              if (entry.tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in entry.tags)
                      TagChip(tag: tag, dense: true),
                  ],
                ),
              ],
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
      required this.onCloseSession,
      required this.onOpenSession});

  final List<ConnectionInfo> sessions;
  final VoidCallback onCloseAll;
  final ValueChanged<ConnectionInfo> onCloseSession;
  final ValueChanged<ConnectionInfo> onOpenSession;

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
                    onOpen: () => onOpenSession(session),
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
  const _SessionRow(
      {required this.session, required this.onOpen, required this.onClose});

  final ConnectionInfo session;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kindLabel =
        (session.kind ?? 'ssh').toUpperCase();
    return InkWell(
      onTap: onOpen,
      child: Padding(
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
                  Text(kindLabel,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(
                    session.hibernated
                        ? 'Hibernated — tap to resume'
                        : 'Active — tap to open',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
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
      ),
    );
  }
}

class _NewSessionSection extends StatelessWidget {
  const _NewSessionSection({required this.entry, required this.onStart});

  final ServerEntry entry;
  final ValueChanged<SessionKind> onStart;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final proto = (entry.protocol ?? '').toLowerCase();
    final isGraphical = proto == 'rdp' || proto == 'vnc';
    final label = proto == 'rdp'
        ? 'RDP'
        : proto == 'vnc'
            ? 'VNC'
            : 'SSH';
    final primaryKind =
        isGraphical ? SessionKind.desktop : SessionKind.terminal;
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
                onPressed: () => onStart(primaryKind),
                icon: Icon(isGraphical ? Icons.monitor : Icons.terminal),
                label: Text(label),
                style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onStart(SessionKind.files),
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
  const _ActionsSection({required this.entry, required this.onAction});

  final ServerEntry entry;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final isSsh =
        (entry.protocol ?? '').toLowerCase() == 'ssh';
    return Column(
      children: [
        _actionTile(context, Icons.bolt, 'Quick connect', 'quick-connect',
            destructive: false),
        _actionTile(context, Icons.play_arrow, 'Run script', 'run-script',
            destructive: false),
        if (isSsh)
          _actionTile(context, Icons.language, 'Browser', 'browser',
              destructive: false),
        _actionTile(context, Icons.drive_file_move_outlined, 'Move',
            'move',
            destructive: false),
        _actionTile(context, Icons.label_outlined, 'Tags', 'tags',
            destructive: false),
        _actionTile(context, Icons.note_outlined, 'Notes', 'notes',
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
        // No pop here: the caller (page handler) closes the sheet.
        onAction(action);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}
