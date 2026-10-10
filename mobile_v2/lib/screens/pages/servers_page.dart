import 'package:flutter/material.dart';

import '../../api/nexterm_api.dart';
import '../../remote/session_opener.dart';
import '../../remote/viewer.dart';
import '../../servers/identity.dart';
import '../../servers/server_models.dart';
import '../../servers/server_repository.dart';
import '../../servers/folder_picker.dart';
import '../../servers/tag_models.dart';
import '../../snippets/snippet_models.dart';
import 'server_detail_sheet.dart';
import 'server_editor_screen.dart';
import 'server_notes_screen.dart';
import 'ssh_import_screen.dart';

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
    this.initialGridView = false,
  });

  final ServerRepository repository;
  final NextermApi api;
  final String token;
  final ConnectionListProvider connections;
  final VoidCallback onSessionExpired;

  /// Initial list/grid mode (device preference).
  final bool initialGridView;

  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  List<EntryNode>? _nodes;
  Map<int, List<ConnectionInfo>> _conns = {};
  String? _error;
  bool _loading = true;
  late bool _gridView;
  bool _gridTouched = false;
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
    _gridView = widget.initialGridView;
    _load();
  }

  @override
  void didUpdateWidget(ServersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // "Grid by default" pref arrives as a constructor param —
    // adopt it unless the user toggled manually this session.
    if (oldWidget.initialGridView != widget.initialGridView &&
        !_gridTouched) {
      setState(() => _gridView = widget.initialGridView);
    }
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

  Future<void> _startSession(ServerEntry entry, SessionKind kind,
      {int? scriptId, String? connectionType}) {
    return startNewSession(context,
        api: widget.api,
        token: widget.token,
        entry: entry,
        kind: kind,
        scriptId: scriptId,
        connectionType: connectionType,
        onSessionExpired: widget.onSessionExpired);
  }

  Future<void> _openExisting(
      ServerEntry entry, ConnectionInfo info) {
    return openConnectionViewer(context,
        api: widget.api,
        token: widget.token,
        entry: entry,
        info: info,
        onSessionExpired: widget.onSessionExpired);
  }

  Future<void> _closeConnection(ConnectionInfo info) async {
    try {
      await SessionOpener(api: widget.api, token: widget.token)
          .close(info.sessionId);
    } on SessionExpiredException {
      widget.onSessionExpired();
      return;
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
      } on SessionExpiredException {
        widget.onSessionExpired();
        return;
      } catch (_) {}
    }
    await _load();
  }

  // -- Entry actions ----------------------------------------------------

  Future<void> _handleAction(ServerEntry entry, String action) async {
    switch (action) {
      case 'quick-connect':
        await _startSession(entry, entry.quickConnectKind);
      case 'run-script':
        await _pickAndRunScript(entry);
      case 'browser':
        await _startSession(entry, SessionKind.desktop,
            connectionType: 'web');
      case 'move':
        await _moveServer(entry);
      case 'tags':
        await _manageTags(entry);
      case 'notes':
        await _openNotes(entry);
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

  /// Script picker (web ScriptsMenu equivalent): run a library script
  /// on this server by opening a terminal session with `scriptId`
  /// (`POST /api/connections/` runs it, output streams to the viewer).
  Future<void> _pickAndRunScript(ServerEntry entry) async {
    List<ScriptEntry> scripts = [];
    var dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator()),
    ).then((_) => dialogOpen = false);
    void closeProgress() {
      if (dialogOpen && context.mounted) {
        dialogOpen = false;
        Navigator.pop(context);
      }
    }

    try {
      final raw = await widget.api.fetchScripts(widget.token);
      for (final m in raw) {
        try {
          scripts.add(ScriptEntry.fromJson(m));
        } catch (_) {}
      }
    } on SessionExpiredException {
      closeProgress();
      widget.onSessionExpired();
      return;
    } on NextermApiException catch (e) {
      closeProgress();
      if (mounted) _snack(e.message);
      return;
    } catch (_) {
      closeProgress();
      if (mounted) _snack('Could not load scripts.');
      return;
    }
    closeProgress();
    if (!mounted) return;
    if (scripts.isEmpty) {
      _snack('No scripts in the library.');
      return;
    }
    final picked = await showModalBottomSheet<ScriptEntry>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text('Run script',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: scripts.length,
                itemBuilder: (_, i) {
                  final script = scripts[i];
                  return ListTile(
                    leading: const Icon(Icons.play_arrow),
                    title: Text(script.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                    onTap: () => Navigator.pop(ctx, script),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _startSession(entry, SessionKind.terminal,
        scriptId: picked.id);
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

  /// Tag manager (web TagsSubmenu equivalent): toggle assignments,
  /// create and delete tags.
  Future<void> _manageTags(ServerEntry entry) async {
    List<TagItem> all = [];
    try {
      final raw = await widget.api.fetchTags(widget.token);
      for (final m in raw) {
        try {
          all.add(TagItem.fromJson(m));
        } catch (_) {}
      }
    } on SessionExpiredException {
      widget.onSessionExpired();
      return;
    } on NextermApiException catch (e) {
      if (mounted) _snack(e.message);
      return;
    } catch (_) {
      if (mounted) _snack('Could not load tags.');
      return;
    }
    if (!mounted) return;
    final assigned = entry.tags.map((t) => t.id).toSet();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _TagManagerSheet(
        api: widget.api,
        token: widget.token,
        entry: entry,
        initial: all,
        assigned: assigned,
        onSessionExpired: widget.onSessionExpired,
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openNotes(ServerEntry entry) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ServerNotesScreen(
            api: widget.api,
            token: widget.token,
            entry: entry,
            onSessionExpired: widget.onSessionExpired),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _openEditor({int? entryId}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ServerEditorScreen(
            api: widget.api,
            token: widget.token,
            entryId: entryId,
            onSessionExpired: widget.onSessionExpired),
      ),
    );
    if (saved == true) await _load();
  }

  /// FAB menu: new server, folder, or SSH-config import.
  Future<void> _fabMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('New server',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, 'server'),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New folder',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, 'folder'),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Import SSH config',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, 'import'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'server') {
      await _openEditor();
    } else if (choice == 'folder') {
      await _createFolder();
    } else if (choice == 'import') {
      final done = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => SshImportScreen(
              api: widget.api,
              token: widget.token,
              onSessionExpired: widget.onSessionExpired),
        ),
      );
      if (done == true) await _load();
    }
  }

  Future<String?> _askFolderName(
      {required String title, String? initial}) async {
    final controller = TextEditingController(text: initial ?? '');
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 50,
            decoration: const InputDecoration(
              labelText: 'Folder name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      ).then((v) => v == null || v.isEmpty ? null : v);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _createFolder({int? parentId}) async {
    final name =
        await _askFolderName(title: 'New folder');
    if (name == null || !mounted) return;
    try {
      final payload = <String, dynamic>{'name': name};
      final pid = parentId;
      if (pid != null) payload['parentId'] = pid;
      await widget.api.createFolder(widget.token, payload);
      if (mounted) _snack('Folder created.');
      await _load();
    } on SessionExpiredException {
      widget.onSessionExpired();
    } on NextermApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Could not create folder.');
    }
  }

  Future<void> _renameFolder(FolderNode folder) async {
    final folderId = int.tryParse(folder.id);
    if (folderId == null) return;
    final name = await _askFolderName(
        title: 'Rename folder', initial: folder.name);
    if (name == null || name == folder.name || !mounted) return;
    try {
      await widget.api
          .renameFolder(widget.token, folderId, {'name': name});
      if (mounted) _snack('Folder renamed.');
      await _load();
    } on SessionExpiredException {
      widget.onSessionExpired();
    } on NextermApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Could not rename folder.');
    }
  }

  Future<void> _deleteFolder(FolderNode folder) async {
    final folderId = int.tryParse(folder.id);
    if (folderId == null) return;
    final childCount = flattenNodes(folder.children).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete folder?'),
        content: Text(childCount == 0
            ? 'Delete "${folder.name}" permanently?'
            : 'Delete "${folder.name}" and all $childCount server${childCount == 1 ? '' : 's'} inside it permanently? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.deleteFolder(widget.token, folderId);
      if (mounted) _snack('Folder deleted.');
      await _load();
    } on SessionExpiredException {
      widget.onSessionExpired();
    } on NextermApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Could not delete folder.');
    }
  }

  void _openFolderActions(FolderNode folder) {
    if (folder.isOrganization) return;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(folder.name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('New subfolder',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                final parentId = int.tryParse(folder.id);
                if (parentId != null) {
                  _createFolder(parentId: parentId);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _renameFolder(folder);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteFolder(folder);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Move a server to another folder (or top level) via `folderId`.
  Future<void> _moveServer(ServerEntry entry) async {
    final nodes = _nodes;
    if (nodes == null || !mounted) return;
    final pick = await showFolderPicker(context, nodes);
    if (pick == null || !mounted) return;
    try {
      await _mutations.update(entry.id, {'folderId': pick.folderId});
      if (mounted) {
        _snack(pick.folderId == null
            ? 'Moved to top level.'
            : 'Server moved.');
      }
      await _load();
    } on SessionExpiredException {
      widget.onSessionExpired();
    } on NextermApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Could not move server.');
    }
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
                      onPressed: () => setState(() {
                        _gridView = !_gridView;
                        _gridTouched = true;
                      }),
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
              tooltip: 'New server or folder',
              onPressed: _fabMenu,
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
                controller: _scrollController,
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
                onFolderMore: () => _openFolderActions(node),
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
      required this.onMore,
      required this.onFolderMore});

  final FolderNode folder;
  final bool expanded;
  final bool gridView;
  final int Function(ServerEntry) openCount;
  final VoidCallback onToggle;
  final ValueChanged<ServerEntry> onTap;
  final ValueChanged<ServerEntry> onMore;
  final VoidCallback onFolderMore;

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
          onLongPress:
              folder.isOrganization ? null : onFolderMore,
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
      required this.onMore,
      this.controller});

  final List<ServerEntry> servers;
  final int Function(ServerEntry) openCount;
  final ValueChanged<ServerEntry> onTap;
  final ValueChanged<ServerEntry> onMore;

  /// When set, the grid scrolls itself (search results); otherwise it
  /// sizes to content for embedding in the folder list.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controller = this.controller;
    return GridView.builder(
      controller: controller,
      shrinkWrap: controller == null,
      physics: controller == null
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: controller == null
          ? const EdgeInsets.only(bottom: 8)
          : const EdgeInsets.fromLTRB(16, 0, 16, 96),
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

/// Tag manager bottom sheet: toggle assignments for one server,
/// create new tags, delete tags.
class _TagManagerSheet extends StatefulWidget {
  const _TagManagerSheet(
      {required this.api,
      required this.token,
      required this.entry,
      required this.initial,
      required this.assigned,
      required this.onSessionExpired});

  final NextermApi api;
  final String token;
  final ServerEntry entry;
  final List<TagItem> initial;
  final Set<int> assigned;
  final VoidCallback onSessionExpired;

  @override
  State<_TagManagerSheet> createState() => _TagManagerSheetState();
}

class _TagManagerSheetState extends State<_TagManagerSheet> {
  late List<TagItem> _tags;
  late Set<int> _assigned;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tags = List.of(widget.initial);
    _assigned = Set.of(widget.assigned);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggle(TagItem tag, bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (on) {
        await widget.api
            .assignTag(widget.token, tag.id, widget.entry.id);
        _assigned.add(tag.id);
      } else {
        await widget.api
            .unassignTag(widget.token, tag.id, widget.entry.id);
        _assigned.remove(tag.id);
      }
    } on SessionExpiredException {
      widget.onSessionExpired();
      return;
    } on NextermApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not update tag.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final name = TextEditingController();
    String color = tagColorPresets.first;
    try {
      final created = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            title: const Text('New tag'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in tagColorPresets)
                      Semantics(
                        label: 'Tag color',
                        selected: color == c,
                        button: true,
                        child: Tooltip(
                          message: 'Tag color',
                          child: GestureDetector(
                            onTap: () =>
                                setDialog(() => color = c),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _parseTagColor(c),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: color == c
                                      ? Theme.of(ctx)
                                          .colorScheme
                                          .onSurface
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, true),
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      );
      if (created != true ||
          name.text.trim().isEmpty ||
          !mounted) {
        return;
      }
      setState(() => _busy = true);
      try {
        final id = await widget.api.createTag(widget.token,
            {'name': name.text.trim(), 'color': color});
        if (!mounted) return;
        setState(() {
          _tags.add(
              TagItem(id: id, name: name.text.trim(), color: color));
          _busy = false;
        });
      } on SessionExpiredException {
        if (mounted) setState(() => _busy = false);
        widget.onSessionExpired();
      } on NextermApiException catch (e) {
        if (mounted) setState(() => _busy = false);
        _snack(e.message);
      } catch (_) {
        if (mounted) setState(() => _busy = false);
        _snack('Could not create tag.');
      }
    } finally {
      name.dispose();
    }
  }

  Future<void> _rename(TagItem tag) async {
    final name = TextEditingController(text: tag.name);
    try {
      final renamed = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename tag'),
          content: TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, name.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (renamed == null ||
          renamed.isEmpty ||
          renamed == tag.name ||
          !mounted) {
        return;
      }
      setState(() => _busy = true);
      try {
        await widget.api
            .updateTag(widget.token, tag.id, {'name': renamed});
        if (!mounted) return;
        setState(() {
          final i = _tags.indexWhere((t) => t.id == tag.id);
          if (i >= 0) {
            _tags[i] =
                TagItem(id: tag.id, name: renamed, color: tag.color);
          }
          _busy = false;
        });
      } on SessionExpiredException {
        if (mounted) setState(() => _busy = false);
        widget.onSessionExpired();
      } on NextermApiException catch (e) {
        if (mounted) setState(() => _busy = false);
        _snack(e.message);
      } catch (_) {
        if (mounted) setState(() => _busy = false);
        _snack('Could not rename tag.');
      }
    } finally {
      name.dispose();
    }
  }

  Future<void> _delete(TagItem tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete tag?'),
        content: Text(
            '"${tag.name}" is removed everywhere. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.deleteTag(widget.token, tag.id);
      if (!mounted) return;
      setState(() {
        _tags.removeWhere((t) => t.id == tag.id);
        _assigned.remove(tag.id);
        _busy = false;
      });
    } on SessionExpiredException {
      if (mounted) setState(() => _busy = false);
      widget.onSessionExpired();
    } on NextermApiException catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack(e.message);
    } catch (_) {
      if (!mounted) setState(() => _busy = false);
      _snack('Could not delete tag.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy)
            const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('Tags · ${widget.entry.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New'),
                ),
              ],
            ),
          ),
          Flexible(
            child: _tags.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No tags yet.',
                        textAlign: TextAlign.center),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _tags.length,
                    itemBuilder: (_, i) {
                      final tag = _tags[i];
                      final on = _assigned.contains(tag.id);
                      return ListTile(
                        leading: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: tag.resolveColor(
                                Theme.of(context)
                                    .colorScheme),
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(tag.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: on,
                              onChanged: _busy
                                  ? null
                                  : (v) => _toggle(
                                      tag, v ?? false),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  size: 20),
                              tooltip: 'Rename tag',
                              onPressed: _busy
                                  ? null
                                  : () => _rename(tag),
                            ),
                            IconButton(
                              icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20),
                              tooltip: 'Delete tag',
                              onPressed: _busy
                                  ? null
                                  : () => _delete(tag),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

Color _parseTagColor(String hex) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) {
    h = 'FF$h';
  } else if (h.length != 8) {
    return const Color(0xFF3F51B5);
  }
  return Color(int.tryParse(h, radix: 16) ?? 0xFF3F51B5);
}
