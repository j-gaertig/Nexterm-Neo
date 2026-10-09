import 'package:flutter/material.dart';

import '../../api/nexterm_api.dart';
import '../../remote/session_opener.dart';
import '../../remote/viewer.dart';
import '../../servers/identity.dart';
import '../../servers/server_models.dart';
import '../../servers/server_repository.dart';
import 'server_detail_sheet.dart';
import 'server_editor_screen.dart';

/// Servers page after the sketch: header with reload, search,
/// grid/list toggle, collapsible folders, server rows/cards with
/// open-session counts and an overflow menu, plus a "+" button.
/// Fully functional against the API (connections excluded from scope
/// only where noted).
class ServersPage extends StatefulWidget {
  const ServersPage({
    super.key,
    required this.repository,
    required this.api,
    required this.token,
    required this.connections,
    required this.onSessionExpired,
  });

  final ServerRepository repository;
  final NextermApi api;
  final String token;
  final ConnectionListProvider connections;
  final VoidCallback onSessionExpired;

  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  List<EntryNode>? _nodes;
  Map<int, List<ConnectionInfo>> _conns = {};
  String? _error;
  bool _loading = true;
  bool _gridView = false;
  String _query = '';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final Set<String> _expanded = {};
  int _loadCalls = 0;

  EntryMutations get _mutations =>
      EntryMutations(api: widget.api, token: widget.token);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final call = ++_loadCalls;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final nodes = await widget.repository.fetchNodes();
      List<ConnectionInfo> conns = const [];
      try {
        conns = await widget.connections.activeSessions();
      } catch (_) {
        // Sessions are best-effort; the list must still render.
      }
      if (!mounted || call != _loadCalls) return;
      final byServer = <int, List<ConnectionInfo>>{};
      for (final c in conns) {
        byServer.putIfAbsent(c.entryId, () => []).add(c);
      }
      setState(() {
        _nodes = nodes;
        _conns = byServer;
        _loading = false;
        for (final id in _allFolderIds(nodes)) {
          _expanded.add(id);
        }
      });
    } on SessionExpiredException {
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onSessionExpired();
    } on NextermApiException catch (e) {
      if (!mounted || call != _loadCalls) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || call != _loadCalls) return;
      setState(() {
        _error = 'Could not load servers.';
        _loading = false;
      });
    }
  }

  Set<String> _allFolderIds(List<EntryNode> nodes) {
    final ids = <String>{};
    void walk(EntryNode node) {
      if (node is FolderNode) {
        ids.add(node.id);
        for (final child in node.children) {
          walk(child);
        }
      }
    }

    for (final node in nodes) {
      walk(node);
    }
    return ids;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // -- Sheets ----------------------------------------------------------

  void _openSessionsSheet(BuildContext sheetContext, ServerEntry entry) {
    showModalBottomSheet<void>(
      context: sheetContext,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ServerDetailSheet.sessions(
        entry: entry,
        sessions: _conns[entry.id] ?? const [],
        onStartSession: (kind) {
          Navigator.pop(ctx);
          _startSession(entry, kind);
        },
        onOpenSession: (info) {
          Navigator.pop(ctx);
          _openExisting(entry, info);
        },
        onCloseSession: (info) => _closeConnection(info),
        onCloseAll: () => _closeAll(entry),
      ),
    );
  }

  void _openActionsSheet(BuildContext sheetContext, ServerEntry entry) {
    showModalBottomSheet<void>(
      context: sheetContext,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ServerDetailSheet.actions(
        entry: entry,
        onAction: (action) {
          Navigator.pop(ctx);
          _handleAction(entry, action);
        },
      ),
    );
  }

  // -- Session handling -------------------------------------------------

  Future<void> _startSession(ServerEntry entry, SessionKind kind) {
    return startNewSession(context,
        api: widget.api, token: widget.token, entry: entry, kind: kind);
  }

  Future<void> _openExisting(
      ServerEntry entry, ConnectionInfo info) {
    return openConnectionViewer(context,
        api: widget.api,
        token: widget.token,
        entry: entry,
        info: info);
  }

  Future<void> _closeConnection(ConnectionInfo info) async {
    try {
      await SessionOpener(api: widget.api, token: widget.token)
          .close(info.sessionId);
    } catch (e) {
      if (mounted) {
        _snack(e is NextermApiException
            ? e.message
            : 'Could not close session.');
      }
      return;
    }
    await _load();
  }

  Future<void> _closeAll(ServerEntry entry) async {
    final opener = SessionOpener(api: widget.api, token: widget.token);
    for (final info in _conns[entry.id] ?? const <ConnectionInfo>[]) {
      try {
        await opener.close(info.sessionId);
      } catch (_) {}
    }
    await _load();
  }

  // -- Entry actions ----------------------------------------------------

  Future<void> _handleAction(ServerEntry entry, String action) async {
    switch (action) {
      case 'quick-connect':
        await _startSession(
            entry,
            entry.primaryProtocol == 'rdp'
                ? SessionKind.desktop
                : SessionKind.terminal);
      case 'wake-on-lan':
        try {
          await _mutations.wake(entry.id);
          if (mounted) _snack('Wake-on-LAN packet sent.');
        } catch (e) {
          if (mounted) {
            _snack(e is NextermApiException
                ? e.message
                : 'Wake-on-LAN failed.');
          }
        }
      case 'duplicate':
        try {
          await _mutations.duplicate(entry.id);
          if (mounted) _snack('Server duplicated.');
          await _load();
        } catch (e) {
          if (mounted) {
            _snack(e is NextermApiException
                ? e.message
                : 'Duplicate failed.');
          }
        }
      case 'delete':
        await _confirmDelete(entry);
      case 'edit':
        await _openEditor(entryId: entry.id);
    }
  }

  Future<void> _confirmDelete(ServerEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete server?'),
        content: Text(
            '"${entry.name}" will be deleted permanently. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _mutations.remove(entry.id);
      if (mounted) _snack('Server deleted.');
      await _load();
    } catch (e) {
      if (mounted) {
        _snack(e is NextermApiException ? e.message : 'Delete failed.');
      }
    }
  }

  Future<void> _openEditor({int? entryId}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ServerEditorScreen(
            api: widget.api, token: widget.token, entryId: entryId),
      ),
    );
    if (saved == true) await _load();
  }

  // -- Filtering --------------------------------------------------------

  List<ServerEntry> _filteredServers() {
    final q = _query.trim().toLowerCase();
    final all = flattenNodes(_nodes ?? const []);
    if (q.isEmpty) return all;
    return all
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            s.ip.toLowerCase().contains(q))
        .toList();
  }

  // -- Build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              _Header(
                loading: _loading,
                onReload: _load,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Search',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) =>
                            setState(() => _query = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      icon: Icon(_gridView
                          ? Icons.view_list_outlined
                          : Icons.grid_view_outlined),
                      tooltip: _gridView ? 'List view' : 'Grid view',
                      onPressed: () =>
                          setState(() => _gridView = !_gridView),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildBody(cs)),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'add-server',
              tooltip: 'New server',
              onPressed: () => _openEditor(),
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading && _nodes == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null && _nodes == null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
    final nodes = _nodes ?? const <EntryNode>[];
    if (nodes.isEmpty) return _EmptyView(onRefresh: _load);

    final searching = _query.trim().isNotEmpty;
    if (searching) {
      final matches = _filteredServers();
      if (matches.isEmpty) {
        return Center(
          child: Text('No servers match "$_query".',
              style: TextStyle(color: cs.onSurfaceVariant)),
        );
      }
      return Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        thickness: 4,
        radius: const Radius.circular(2),
        child: _gridView
            ? _ServerGrid(
                servers: matches,
                openCount: _openCount,
                onTap: (s) => _openSessionsSheet(context, s),
                onMore: (s) => _openActionsSheet(context, s),
              )
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                itemCount: matches.length,
                itemBuilder: (context, index) => _ServerTile(
                  entry: matches[index],
                  openCount: _openCount(matches[index]),
                  onTap: () =>
                      _openSessionsSheet(context, matches[index]),
                  onMore: () =>
                      _openActionsSheet(context, matches[index]),
                ),
              ),
      );
    }

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      thickness: 4,
      radius: const Radius.circular(2),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        itemCount: nodes.length,
        itemBuilder: (context, index) {
          final node = nodes[index];
          switch (node) {
            case ServerNode(:final entry):
              if (_gridView) {
                return _ServerGrid(
                  servers: [entry],
                  openCount: _openCount,
                  onTap: (s) => _openSessionsSheet(context, s),
                  onMore: (s) => _openActionsSheet(context, s),
                );
              }
              return _ServerTile(
                entry: entry,
                openCount: _openCount(entry),
                onTap: () => _openSessionsSheet(context, entry),
                onMore: () => _openActionsSheet(context, entry),
              );
            case FolderNode():
              return _FolderSection(
                folder: node,
                expanded: _expanded.contains(node.id),
                gridView: _gridView,
                openCount: _openCount,
                onToggle: () => setState(() {
                  if (_expanded.contains(node.id)) {
                    _expanded.remove(node.id);
                  } else {
                    _expanded.add(node.id);
                  }
                }),
                onTap: (s) => _openSessionsSheet(context, s),
                onMore: (s) => _openActionsSheet(context, s),
              );
          }
        },
      ),
    );
  }

  int _openCount(ServerEntry entry) =>
      _conns[entry.id]?.length ?? 0;
}

class _Header extends StatelessWidget {
  const _Header({required this.loading, required this.onReload});

  final bool loading;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/logo.png',
              width: 28,
              height: 28,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.terminal, size: 24),
            ),
          ),
          const SizedBox(width: 10),
          Text('Nexterm',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const Spacer(),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload',
              onPressed: onReload,
            ),
        ],
      ),
    );
  }
}

class _FolderSection extends StatelessWidget {
  const _FolderSection(
      {required this.folder,
      required this.expanded,
      required this.gridView,
      required this.openCount,
      required this.onToggle,
      required this.onTap,
      required this.onMore});

  final FolderNode folder;
  final bool expanded;
  final bool gridView;
  final int Function(ServerEntry) openCount;
  final VoidCallback onToggle;
  final ValueChanged<ServerEntry> onTap;
  final ValueChanged<ServerEntry> onMore;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final servers = flattenNodes(folder.children);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.folder_open : Icons.folder_outlined,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${folder.name} (${servers.length})',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          if (gridView)
            _ServerGrid(
              servers: servers,
              openCount: openCount,
              onTap: onTap,
              onMore: onMore,
            )
          else
            for (final server in servers)
              _ServerTile(
                entry: server,
                openCount: openCount(server),
                onTap: () => onTap(server),
                onMore: () => onMore(server),
              ),
      ],
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
      {required this.entry,
      required this.openCount,
      required this.onTap,
      required this.onMore});

  final ServerEntry entry;
  final int openCount;
  final VoidCallback onTap;
  final VoidCallback onMore;

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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (openCount > 0) _OpenBadge(count: openCount),
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Server actions',
              onPressed: onMore,
            ),
          ],
        ),
        onTap: onTap,
        onLongPress: onMore,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding:
            const EdgeInsets.only(left: 16, right: 4, top: 4, bottom: 4),
      ),
    );
  }
}

class _ServerGrid extends StatelessWidget {
  const _ServerGrid(
      {required this.servers,
      required this.openCount,
      required this.onTap,
      required this.onMore});

  final List<ServerEntry> servers;
  final int Function(ServerEntry) openCount;
  final ValueChanged<ServerEntry> onTap;
  final ValueChanged<ServerEntry> onMore;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 148,
      ),
      itemCount: servers.length,
      itemBuilder: (context, index) {
        final entry = servers[index];
        final count = openCount(entry);
        return Card(
          elevation: 0,
          color: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onTap(entry),
            onLongPress: () => onMore(entry),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(protocolIcon(entry.protocol),
                            color: cs.onPrimaryContainer, size: 18),
                      ),
                      const Spacer(),
                      if (count > 0) _OpenBadge(count: count),
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => onMore(entry),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.more_vert, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(entry.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(formatServerSubtitle(entry),
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OpenBadge extends StatelessWidget {
  const _OpenBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$count open',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.onPrimaryContainer)),
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
