import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/app_icons.dart';
import '../models/server.dart';
import '../models/server_folder.dart';
import '../services/server_service.dart';
import '../services/session_manager.dart';
import '../utils/auth_manager.dart';
import '../utils/snippet_manager.dart';
import '../utils/folder_state_manager.dart';
import '../utils/server_view_settings.dart';
import 'widgets/quick_connect_sheet.dart';
import 'widgets/connection_reason_dialog.dart';

class ServersScreen extends StatefulWidget {
  final AuthManager authManager;
  final SnippetManager snippetManager;
  final SessionManager sessionManager;
  final ServerViewSettings serverViewSettings;
  final VoidCallback? onSwitchToSessions;

  const ServersScreen({super.key, required this.authManager, required this.snippetManager, required this.sessionManager, required this.serverViewSettings, this.onSwitchToSessions});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  List<dynamic> folders = [];
  List<dynamic> filteredFolders = [];
  bool isLoading = true;
  String? errorMessage;
  FolderStateManager? _folderState;
  final Set<String> _expanded = {};
  final _search = TextEditingController();
  String _query = '';
  Timer? _debounce;
  bool _searchFocused = false;
  bool _hasText = false;
  final Set<int> _selectedTags = {};
  List<Tag> _allTags = [];

  String _folderKey(ServerFolder folder) {
    final id = folder.id;
    if (id != null) return 'id:$id';
    return 'n:${folder.type}:${folder.name}:${folder.position}';
  }

  int get _totalServers => folders.fold(0, (sum, item) => sum + _countServers(item));
  int _countServers(dynamic item) {
    if (item is Server) return 1;
    if (item is ServerFolder) return item.allServers.length + item.allFolders.fold(0, (sum, sf) => sum + _countServers(sf));
    return 0;
  }
  int get _onlineServers => folders.fold(0, (sum, item) => sum + _countOnline(item));
  int _countOnline(dynamic item) {
    if (item is Server) return item.isRunning ? 1 : 0;
    if (item is ServerFolder) return item.allServers.where((s) => s.isRunning).length + item.allFolders.fold(0, (sum, sf) => sum + _countOnline(sf));
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _hasText = _search.text.isNotEmpty;
    _search.addListener(_onSearch);
    _initStateManager();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.removeListener(_onSearch);
    _search.dispose();
    super.dispose();
  }

  void _onSearch() {
    final hasText = _search.text.isNotEmpty;
    if (hasText != _hasText && mounted) setState(() => _hasText = hasText);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() { _query = _search.text.trim(); _filterFolders(); });
    });
  }

  void _clearSearch() {
    _search.clear();
    _debounce?.cancel();
    if (mounted) setState(() { _query = ''; _hasText = false; _filterFolders(); });
  }

  Future<void> _initStateManager() async {
    _folderState = await FolderStateManager.create();
    await _loadData();
  }

  Future<void> _loadData() async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final token = widget.authManager.sessionToken;
      if (token == null) { if (mounted) setState(() { errorMessage = 'Not authenticated'; isLoading = false; }); return; }
      final data = await ServerService.getServerList(token);
      final tags = _collectTags(data);
      final validTagIds = tags.map((t) => t.id).toSet();
      _selectedTags.removeWhere((id) => !validTagIds.contains(id));
      if (!mounted) return;
      setState(() {
        folders = data;
        _allTags = tags;
        isLoading = false;
        errorMessage = null;
        _expanded.clear();
        if (_folderState != null) _restoreStates(data);
        _filterFolders();
      });
      _pruneStaleFolderStates(data);
    } catch (e) {
      if (mounted) setState(() { errorMessage = 'Failed to load servers: $e'; isLoading = false; });
    }
  }

  List<Tag> _collectTags(List<dynamic> list) {
    final map = <int, Tag>{};
    for (final item in list) {
      if (item is Server) {
        for (final t in item.tags ?? <Tag>[]) { map[t.id] = t; }
      } else if (item is ServerFolder) {
        for (final s in item.allServers) {
          for (final t in s.tags ?? <Tag>[]) { map[t.id] = t; }
        }
        for (final t in _collectTags(item.allFolders)) { map[t.id] = t; }
      }
    }
    return map.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  bool _serverMatchesTags(Server s) => _selectedTags.isEmpty || (s.tags?.any((t) => _selectedTags.contains(t.id)) ?? false);

  void _filterFolders() {
    if (_query.trim().isEmpty && _selectedTags.isEmpty) { filteredFolders = List.from(folders); return; }
    filteredFolders = folders.map((item) {
      if (item is ServerFolder) return _filterFolder(item);
      if (item is Server) return _serverMatches(item) ? item : null;
      return null;
    }).where((e) => e != null).toList();
  }

  bool _serverMatches(Server s) {
    final matchesTag = _serverMatchesTags(s);
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return matchesTag;
    return matchesTag && (s.name.toLowerCase().contains(q) || s.ip.toLowerCase().contains(q));
  }

  bool _tagMatches(Server s) => _serverMatchesTags(s);

  List<dynamic> _tagOnlyEntries(ServerFolder folder) {
    final List<dynamic> out = [];
    for (final e in folder.entries) {
      if (e is! Map<String, dynamic>) continue;
      final type = e['type'] as String?;
      if (type == 'server' || (type?.startsWith('pve-') == true)) {
        final s = Server.fromJson(Map<String, dynamic>.from(e));
        if (_tagMatches(s)) out.add(e);
      } else if (type == 'folder' || type == 'organization') {
        final sub = ServerFolder.fromJson(Map<String, dynamic>.from(e));
        final kept = _tagOnlyFolder(sub);
        if (kept != null) out.add(kept.toJson());
      }
    }
    return out;
  }

  ServerFolder? _tagOnlyFolder(ServerFolder folder) {
    final kept = _tagOnlyEntries(folder);
    if (kept.isEmpty) return null;
    return ServerFolder(
      id: folder.id, name: folder.name, type: folder.type, position: folder.position,
      organizationId: folder.organizationId, requireConnectionReason: folder.requireConnectionReason,
      entries: kept,
      ip: folder.ip, icon: folder.icon, folderType: folder.folderType,
    );
  }

  ServerFolder? _filterFolder(ServerFolder folder) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty && _selectedTags.isEmpty) return folder;
    final matchesName = q.isNotEmpty && folder.name.toLowerCase().contains(q);
    if (matchesName) {
      final tagEntries = _tagOnlyEntries(folder);
      if (tagEntries.isNotEmpty) {
        return ServerFolder(
          id: folder.id, name: folder.name, type: folder.type, position: folder.position,
          organizationId: folder.organizationId, requireConnectionReason: folder.requireConnectionReason,
          entries: tagEntries,
          ip: folder.ip, icon: folder.icon, folderType: folder.folderType,
        );
      }
      return null;
    }
    final List<dynamic> kept = [];
    for (final e in folder.entries) {
      if (e is! Map<String, dynamic>) continue;
      final type = e['type'] as String?;
      if (type == 'server' || (type?.startsWith('pve-') == true)) {
        final s = Server.fromJson(Map<String, dynamic>.from(e));
        if (_serverMatches(s)) kept.add(e);
      } else if (type == 'folder' || type == 'organization') {
        final sub = ServerFolder.fromJson(Map<String, dynamic>.from(e));
        final f = _filterFolder(sub);
        if (f != null) kept.add(f.toJson());
      }
    }
    if (kept.isNotEmpty) {
      return ServerFolder(
        id: folder.id, name: folder.name, type: folder.type, position: folder.position,
        organizationId: folder.organizationId, requireConnectionReason: folder.requireConnectionReason,
        entries: kept,
        ip: folder.ip, icon: folder.icon, folderType: folder.folderType,
      );
    }
    return null;
  }

  Future<void> _refreshData() async {
    try {
      final token = widget.authManager.sessionToken;
      if (token == null) return;
      final data = await ServerService.getServerList(token);
      final tags = _collectTags(data);
      final validTagIds = tags.map((t) => t.id).toSet();
      _selectedTags.removeWhere((id) => !validTagIds.contains(id));
      if (!mounted) return;
      setState(() {
        folders = data;
        _allTags = tags;
        errorMessage = null;
        _expanded.clear();
        if (_folderState != null) _restoreStates(data);
        _filterFolders();
      });
      _pruneStaleFolderStates(data);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to refresh: $e'), behavior: SnackBarBehavior.floating));
    }
  }

  void _restoreStates(List<dynamic> list) {
    for (final item in list) {
      if (item is ServerFolder) {
        if (_folderState != null && item.id != null && _folderState!.isFolderExpanded(item.id)) {
          _expanded.add(_folderKey(item));
        }
        if (item.allFolders.isNotEmpty) _restoreStates(item.allFolders);
      }
    }
  }

  void _pruneStaleFolderStates(List<dynamic> list) {
    final state = _folderState;
    if (state == null) return;
    final valid = <String>{};
    void collect(List<dynamic> items) {
      for (final item in items) {
        if (item is ServerFolder) {
          valid.add(_folderKey(item));
          collect(item.allFolders);
        }
      }
    }
    collect(list);
    _expanded.removeWhere((k) => !valid.contains(k));
    for (final id in state.getAllExpandedFolderIds()) {
      if (!valid.contains('id:$id')) {
        state.setFolderExpanded(id, false);
      }
    }
  }

  Future<void> _toggleFolder(ServerFolder folder) async {
    final key = _folderKey(folder);
    _expanded.contains(key) ? _expanded.remove(key) : _expanded.add(key);
    final shouldExpand = _expanded.contains(key);
    if (_folderState != null && folder.id != null) {
      await _folderState!.setFolderExpanded(folder.id, shouldExpand);
      if (!mounted) return;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _buildHeader(cs, tt),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.serverViewSettings,
              builder: (_, __) => isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : errorMessage != null ? _buildError(cs, tt) : filteredFolders.isEmpty ? _buildEmpty(cs, tt) : _buildList(cs),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, TextTheme tt) {
    final sessions = widget.sessionManager.sessionCount;
    final total = _totalServers;
    final online = _onlineServers;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Servers', style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (!isLoading && errorMessage == null && total > 0)
              Padding(padding: const EdgeInsets.only(top: 2),
                child: Text('$online of $total online', style: tt.bodySmall?.copyWith(color: cs.outline))),
          ])),
          if (sessions > 0)
            ListenableBuilder(listenable: widget.sessionManager, builder: (_, __) {
              final count = widget.sessionManager.sessionCount;
              if (count == 0) return const SizedBox.shrink();
              return GestureDetector(
                onTap: () => widget.onSwitchToSessions?.call(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(AppIcons.monitorMultiple, size: 16, color: cs.onPrimaryContainer),
                    const SizedBox(width: 6),
                    Text('$count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
                  ]),
                ),
              );
            }),
        ]),
        const SizedBox(height: 16),
        Focus(
          onFocusChange: (f) => setState(() => _searchFocused = f),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search servers...',
              prefixIcon: Icon(AppIcons.magnify, size: 22),
              suffixIcon: _hasText
                  ? IconButton(icon: Icon(AppIcons.close, size: 20), tooltip: 'Clear search', onPressed: _clearSearch)
                  : null,
              filled: true,
              fillColor: _searchFocused ? cs.surfaceContainerHighest : cs.surfaceContainerHigh,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary, width: 1.5)),
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
          ),
        ),
        if (_allTags.isNotEmpty) ...[const SizedBox(height: 8), _buildTagBar(cs)],
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _buildTagBar(ColorScheme cs) => SizedBox(
    height: 40,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _allTags.length + (_selectedTags.isNotEmpty ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(width: 6),
      itemBuilder: (_, i) {
        if (_selectedTags.isNotEmpty && i == 0) {
          return Semantics(
            button: true,
            label: 'Clear tag filters',
            child: InkWell(
              onTap: () => setState(() { _selectedTags.clear(); _filterFolders(); }),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Icon(AppIcons.close, size: 16, color: cs.onErrorContainer),
              ),
            ),
          );
        }
        final idx = _selectedTags.isNotEmpty ? i - 1 : i;
        final tag = _allTags[idx];
        final sel = _selectedTags.contains(tag.id);
        final tagColor = _parseColor(tag.color);
        return Semantics(
          button: true,
          selected: sel,
          label: 'Filter by ${tag.name}',
          child: InkWell(
            onTap: () => setState(() {
              sel ? _selectedTags.remove(tag.id) : _selectedTags.add(tag.id);
              _filterFolders();
            }),
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: sel ? tagColor.withValues(alpha: 0.2) : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                border: sel ? Border.all(color: tagColor, width: 1.5) : Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
              ),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: tagColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(tag.name, style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w600 : FontWeight.w500, color: sel ? tagColor : cs.onSurface)),
              ]),
            ),
          ),
        );
      },
    ),
  );

  Widget _buildError(ColorScheme cs, TextTheme tt) => Center(
    child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: cs.errorContainer, shape: BoxShape.circle),
        child: Icon(AppIcons.alertCircleOutline, size: 32, color: cs.onErrorContainer),
      ),
      const SizedBox(height: 20),
      Text('Something went wrong', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text(errorMessage!, style: tt.bodySmall?.copyWith(color: cs.outline), textAlign: TextAlign.center),
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: _loadData, icon: Icon(AppIcons.refresh, size: 18), label: const Text('Retry'),
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ])),
  );

  bool get _hasActiveFilter => _query.trim().isNotEmpty || _selectedTags.isNotEmpty;

  Widget _buildEmpty(ColorScheme cs, TextTheme tt) => RefreshIndicator(
    onRefresh: _refreshData,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [SizedBox(
      height: MediaQuery.of(context).size.height * 0.5,
      child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle),
          child: Icon(AppIcons.serverOff, size: 32, color: cs.outline),
        ),
        const SizedBox(height: 20),
        Text(_hasActiveFilter ? 'No results' : 'No servers yet', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(_hasActiveFilter ? 'Try a different search term or clear filters' : 'Add servers from the web dashboard',
          style: tt.bodySmall?.copyWith(color: cs.outline), textAlign: TextAlign.center),
        if (_hasActiveFilter) ...[
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () { _selectedTags.clear(); _clearSearch(); },
            icon: Icon(AppIcons.close, size: 16),
            label: const Text('Clear filters'),
          ),
        ],
      ])),
    )]),
  );

  Widget _buildList(ColorScheme cs) {
    if (!widget.serverViewSettings.isGrid) {
      return RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(left: 8, right: 8, bottom: 16, top: 4),
          itemCount: filteredFolders.length,
          itemBuilder: (_, i) {
            final e = filteredFolders[i];
            if (e is ServerFolder) {
              return _buildFolder(e, 0, key: ValueKey('folder:${e.id ?? e.name}:${e.type}:${e.position}'));
            }
            if (e is Server) {
              return _buildServer(e, 0, key: ValueKey('server:${e.id ?? e.name}'));
            }
            return const SizedBox.shrink();
          },
        ),
      );
    }
    final topServers = filteredFolders.whereType<Server>().toList();
    final rest = filteredFolders.where((e) => e is! Server).toList();
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(left: 8, right: 8, bottom: 16, top: 4),
        itemCount: (topServers.isNotEmpty ? 1 : 0) + rest.length,
        itemBuilder: (_, i) {
          if (topServers.isNotEmpty && i == 0) return _buildServerGrid(topServers, 0);
          final e = rest[topServers.isNotEmpty ? i - 1 : i];
          return _buildEntry(e, 0);
        },
      ),
    );
  }

  Widget _buildEntry(dynamic entry, int depth) {
    if (entry is ServerFolder) {
      return _buildFolder(entry, depth, key: ValueKey('folder:${entry.id ?? entry.name}:${entry.type}:${entry.position}'));
    }
    if (entry is Server) return _buildServer(entry, depth, key: ValueKey('server:${entry.id ?? entry.name}'));
    return const SizedBox.shrink();
  }

  Widget _buildFolder(ServerFolder folder, int depth, {Key? key}) {
    final cs = Theme.of(context).colorScheme;
    final hasEntries = folder.entries.isNotEmpty;
    final open = _expanded.contains(_folderKey(folder));
    final serverCount = folder.allServers.length + folder.allFolders.fold(0, (sum, f) => sum + _countServers(f));
    final cappedDepth = depth.clamp(0, 2);

    final (icon, color) = folder.isOrganization
        ? (open ? AppIcons.brandDomain : AppIcons.brandDomainOff, cs.primary)
        : folder.isPveNode
            ? (AppIcons.brandServer, cs.tertiary)
            : (open ? AppIcons.brandFolderOpen : AppIcons.brandFolder, cs.primary);

    return Column(key: key, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: EdgeInsets.only(left: 12.0 + cappedDepth * 16, right: 12, top: depth == 0 ? 4 : 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: hasEntries ? () => _toggleFolder(folder) : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: color, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(folder.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  if (serverCount > 0) Text('$serverCount server${serverCount == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 11, color: cs.outline)),
                ])),
                if (hasEntries)
                  AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 200),
                    child: Icon(AppIcons.chevronDown, color: cs.outline, size: 20)),
              ]),
            ),
          ),
        ),
      ),
      AnimatedCrossFade(
        firstChild: const SizedBox(width: double.infinity),
        secondChild: open
            ? Column(children: [
                if (folder.allServers.isNotEmpty)
                  widget.serverViewSettings.isGrid
                      ? _buildServerGrid(folder.allServers, depth + 1)
                      : Column(children: [for (final s in folder.allServers) _buildServer(s, depth + 1, key: ValueKey('server:${s.id ?? s.name}'))]),
                for (final f in folder.allFolders)
                  _buildFolder(f, depth + 1, key: ValueKey('folder:${f.id ?? f.name}:${f.type}:${f.position}')),
              ])
            : const SizedBox(width: double.infinity),
        crossFadeState: open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        duration: const Duration(milliseconds: 200),
        sizeCurve: Curves.easeInOut,
      ),
    ]);
  }

  int _effectiveColumns(int wanted) {
    return wanted.clamp(2, 4);
  }

  double _gridRatio(int columns) {
    if (columns <= 2) return 0.78;
    if (columns == 3) return 0.64;
    return 0.54;
  }

  Widget _buildServerGrid(List<Server> servers, int depth) {
    final columns = _effectiveColumns(widget.serverViewSettings.gridColumns);
    final cappedDepth = depth.clamp(0, 2);
    return Padding(
      padding: EdgeInsets.only(left: 12.0 + cappedDepth * 16, right: 12, top: 4, bottom: 4),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: _gridRatio(columns),
        ),
        itemCount: servers.length,
        itemBuilder: (_, i) => _buildServerGridCard(servers[i], compact: columns >= 3, key: ValueKey('grid:${servers[i].id ?? servers[i].name}')),
      ),
    );
  }

  Widget _buildServerGridCard(Server server, {Key? key, bool compact = false}) {
    final cs = Theme.of(context).colorScheme;
    final offline = !server.isRunning;
    final pve = server.isPve;
    final icon = _serverIcon(server);
    final (bg, fg) = offline
        ? (cs.surfaceContainerHighest, cs.outline)
        : pve ? (cs.tertiaryContainer, cs.onTertiaryContainer) : (cs.primaryContainer, cs.onPrimaryContainer);
    String? sub;
    final ip = server.ip.trim();
    if (pve && server.status != null) {
      sub = ip.isNotEmpty && ip != 'N/A' ? '${server.status} · $ip' : server.status;
    } else if (ip.isNotEmpty && ip != 'N/A') {
      sub = ip;
    }
    final tags = server.tags ?? const <Tag>[];
    final statusLabel = offline ? 'Offline' : 'Online';
    return Semantics(
      key: key,
      button: true,
      label: '${server.name}, $statusLabel${sub != null ? ', $sub' : ''}',
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _connectToServer(server),
          onLongPress: () => _showServerMenu(server),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: compact ? 32 : 40, height: compact ? 32 : 40,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(compact ? 10 : 12)),
                child: Center(child: Icon(icon, color: fg, size: compact ? 17 : 20)),
              ),
              SizedBox(height: compact ? 8 : 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(server.name,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: offline ? cs.outline : cs.onSurface),
                    maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis),
                  if (sub != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(sub, style: TextStyle(fontSize: 11, color: cs.outline), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ]),
              ),
              SizedBox(
                height: 24,
                child: tags.isEmpty
                    ? const SizedBox.shrink()
                    : ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [Colors.white, Colors.white, Colors.transparent],
                          stops: [0.0, 0.88, 1.0],
                        ).createShader(bounds),
                        blendMode: BlendMode.dstIn,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final t in tags)
                                Semantics(
                                  button: true,
                                  label: 'Filter by ${t.name}',
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => setState(() {
                                      _selectedTags.contains(t.id) ? _selectedTags.remove(t.id) : _selectedTags.add(t.id);
                                      _filterFolders();
                                    }),
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _parseColor(t.color).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(color: _parseColor(t.color).withValues(alpha: 0.5), width: 1),
                                      ),
                                      child: Text(t.name,
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _parseColor(t.color)),
                                        maxLines: 1, softWrap: false),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildServer(Server server, int depth, {Key? key}) {
    final cs = Theme.of(context).colorScheme;
    final offline = !server.isRunning;
    final pve = server.isPve;
    final icon = _serverIcon(server);

    final (bg, fg) = offline
        ? (cs.surfaceContainerHighest, cs.outline)
        : pve ? (cs.tertiaryContainer, cs.onTertiaryContainer) : (cs.primaryContainer, cs.onPrimaryContainer);

    String? sub;
    final ip = server.ip.trim();
    if (pve && server.status != null) {
      sub = ip.isNotEmpty && ip != 'N/A' ? '${server.status} · $ip' : server.status;
    } else if (ip.isNotEmpty && ip != 'N/A') {
      sub = ip;
    }
    final tags = server.tags ?? const <Tag>[];
    final shownTags = tags.take(3).toList();
    final extraTags = tags.length - shownTags.length;
    final cappedDepth = depth.clamp(0, 2);
    final statusLabel = offline ? 'Offline' : 'Online';

    return Semantics(
      button: true,
      label: '${server.name}, $statusLabel${sub != null ? ', $sub' : ''}',
      child: Padding(
      key: key,
      padding: EdgeInsets.only(left: 12.0 + cappedDepth * 16, right: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _connectToServer(server),
          onLongPress: () => _showServerMenu(server),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                child: Center(child: Icon(icon, color: fg, size: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(server.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: offline ? cs.outline : cs.onSurface), overflow: TextOverflow.ellipsis),
                if (sub != null) Padding(padding: const EdgeInsets.only(top: 2),
                  child: Text(sub, style: TextStyle(fontSize: 12, color: cs.outline), overflow: TextOverflow.ellipsis)),
              ])),
              if (tags.isNotEmpty)
                Padding(padding: const EdgeInsets.only(right: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final t in shownTags)
                      Container(
                        width: 8, height: 8, margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(color: _parseColor(t.color), shape: BoxShape.circle),
                      ),
                    if (extraTags > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text('+$extraTags', style: TextStyle(fontSize: 10, color: cs.outline)),
                      ),
                  ])),
              Icon(AppIcons.chevronRight, color: cs.outlineVariant, size: 18),
            ]),
          ),
        ),
      ),
      ),
    );
  }

  Future<void> _initiateConnection(Server server,
      {ConnectionType type = ConnectionType.terminal, Map<String, dynamic>? directIdentity}) async {
    final token = widget.authManager.sessionToken;
    if (token == null) return;

    String? connectionReason;
    if (_requiresConnectionReason(server)) {
      connectionReason = await showConnectionReasonDialog(context, server.name);
      if (connectionReason == null || !mounted) return;
    }

    try {
      switch (type) {
        case ConnectionType.guacamole:
          await widget.sessionManager.createGuacSession(
            token: token, server: server, directIdentity: directIdentity, connectionReason: connectionReason);
        case ConnectionType.terminal:
          await widget.sessionManager.createTerminalSession(
            token: token, server: server, directIdentity: directIdentity, connectionReason: connectionReason);
        case ConnectionType.sftp:
          await widget.sessionManager.createSftpSession(
            token: token, server: server, directIdentity: directIdentity, connectionReason: connectionReason);
      }
      if (mounted) widget.onSwitchToSessions?.call();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to connect: $e'), behavior: SnackBarBehavior.floating));
    }
  }

  bool _requiresConnectionReason(Server server) {
    final id = _serverIdInt(server.id);
    if (id == null) return false;
    return _findOrganizationForServer(id, folders)?.requireConnectionReason ?? false;
  }

  ServerFolder? _findOrganizationForServer(int serverId, List<dynamic> items, [ServerFolder? currentOrg]) {
    for (final item in items) {
      if (item is Server) {
        if (_serverIdInt(item.id) == serverId) return currentOrg;
      } else if (item is ServerFolder) {
        final org = item.isOrganization ? item : currentOrg;
        final found = _findOrganizationForServer(serverId, [...item.allServers, ...item.allFolders], org);
        if (found != null) return found;
      }
    }
    return null;
  }

  int? _serverIdInt(dynamic id) => id is int ? id : int.tryParse(id.toString());

  void _showServerMenu(Server server) {
    final cs = Theme.of(context).colorScheme;
    final showQuick = server.isServer && !server.isPve;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          margin: const EdgeInsets.only(top: 12, bottom: 4), width: 36, height: 4,
          decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
              child: Icon(_serverIcon(server), color: cs.onPrimaryContainer, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(server.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              if (server.ip.isNotEmpty && server.ip != 'N/A')
                Text(server.ip, style: TextStyle(fontSize: 12, color: cs.outline)),
            ])),
          ]),
        ),
        const SizedBox(height: 8),
        _menuItem(ctx, AppIcons.connection, 'Connect', cs, () {
          Navigator.pop(ctx); _connectToServer(server);
        }),
        if (showQuick)
          _menuItem(ctx, AppIcons.cursorDefaultClick, 'Quick Connect', cs, () {
            Navigator.pop(ctx); _quickConnect(server);
          }),
        if (server.canWakeOnLan)
          _menuItem(ctx, AppIcons.powerPlug, 'Wake-On-LAN', cs, () {
            Navigator.pop(ctx); _wakeServer(server);
          }),
        const SizedBox(height: 12),
      ])),
    );
  }

  Widget _menuItem(BuildContext ctx, IconData icon, String title, ColorScheme cs, VoidCallback onTap) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(children: [
              Icon(icon, size: 22, color: cs.primary),
              const SizedBox(width: 16),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      );

  Future<void> _quickConnect(Server server) async {
    if (server.isPve) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Quick Connect is not supported for Proxmox entries'), behavior: SnackBarBehavior.floating));
      return;
    }

    if (server.protocol?.toLowerCase() == 'telnet') {
      _initiateConnection(server);
      return;
    }

    final directIdentity = await showQuickConnectSheet(context, server);
    if (directIdentity == null || !mounted) return;

    final isFileProtocolForQuickConnect = const {'sftp', 'ftp', 'ftps'}.contains(server.protocol?.toLowerCase());
    _initiateConnection(
      server,
      type: ServerService.isGuacamoleProtocol(server.protocol)
          ? ConnectionType.guacamole
          : isFileProtocolForQuickConnect
              ? ConnectionType.sftp
              : ConnectionType.terminal,
      directIdentity: directIdentity,
    );
  }

  Future<void> _wakeServer(Server server) async {
    final token = widget.authManager.sessionToken;
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Not authenticated'), behavior: SnackBarBehavior.floating));
      }
      return;
    }
    final entryId = server.id;
    if (entryId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to send magic packet: missing server id'), behavior: SnackBarBehavior.floating));
      }
      return;
    }
    try {
      await ServerService.wakeServer(token: token, entryId: entryId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Magic packet sent to ${server.name}'), behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to send magic packet: $e'), behavior: SnackBarBehavior.floating));
    }
  }

  void _connectToServer(Server server) {
    final cs = Theme.of(context).colorScheme;
    if (server.isStopped) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${server.name} is ${server.isPve ? "not running" : "offline"}'), behavior: SnackBarBehavior.floating));
      return;
    }
    final hasIdentities = server.identities?.isNotEmpty == true;
    if (!server.isPve && !hasIdentities) {
      _quickConnect(server);
      return;
    }
    if (ServerService.isGuacamoleProtocol(server.protocol) || server.type == 'pve-qemu') {
      _initiateConnection(server, type: ConnectionType.guacamole);
      return;
    }
    final protocolLower = server.protocol?.toLowerCase();
    final isFileProtocol = protocolLower == 'sftp' || protocolLower == 'ftp' || protocolLower == 'ftps';
    if (isFileProtocol) {
      _initiateConnection(server, type: ConnectionType.sftp);
      return;
    }
    final isSSH = protocolLower == 'ssh' && !server.isPve;
    if (!isSSH) {
      _initiateConnection(server);
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          margin: const EdgeInsets.only(top: 12, bottom: 4), width: 36, height: 4,
          decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
              child: Icon(_serverIcon(server), color: cs.onPrimaryContainer, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(server.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              if (server.ip.isNotEmpty && server.ip != 'N/A')
                Text(server.ip, style: TextStyle(fontSize: 12, color: cs.outline), overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
          Expanded(child: _connectionOption(ctx, AppIcons.consoleLine, 'Terminal', 'SSH session', cs, () {
            Navigator.pop(ctx); _initiateConnection(server);
          })),
          const SizedBox(width: 10),
          Expanded(child: _connectionOption(ctx, AppIcons.folderOutline, 'SFTP', 'File manager', cs, () {
            Navigator.pop(ctx); _initiateConnection(server, type: ConnectionType.sftp);
          })),
        ])),
        const SizedBox(height: 16),
      ])),
    );
  }

  Widget _connectionOption(BuildContext ctx, IconData icon, String title, String sub, ColorScheme cs, VoidCallback onTap) =>
    Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          child: Column(children: [
            Icon(icon, color: cs.primary, size: 28),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(fontSize: 11, color: cs.outline)),
          ]),
        ),
      ),
    );

  IconData _serverIcon(Server server) {
    final icon = server.icon;
    if (icon != null && icon.startsWith('mdi') && icon.length > 3) {
      final camel = icon.substring(3, 4).toLowerCase() + icon.substring(4);
      final hit = AppIcons.resolveBackendIcon(camel);
      if (hit != null) return hit;
    }
    if (server.type == 'pve-lxc') return AppIcons.brandCube;
    if (server.type == 'pve-qemu') return AppIcons.brandMonitor;
    if (server.type == 'pve-shell') return AppIcons.brandConsole;
    final p = server.protocol?.toLowerCase();
    if (p == 'rdp') return AppIcons.brandWindows;
    if (p == 'vnc') return AppIcons.brandRemoteDesktop;
    return AppIcons.brandServer;
  }

  Color _parseColor(String c) {
    if (c.startsWith('#')) {
      try {
        final hex = c.substring(1);
        if (hex.length == 3) {
          final r = hex[0] + hex[0];
          final g = hex[1] + hex[1];
          final b = hex[2] + hex[2];
          return Color(int.parse('FF$r$g$b', radix: 16));
        }
        if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
        if (hex.length == 8) return Color(int.parse(hex, radix: 16));
      } catch (_) {}
    }
    return Theme.of(context).colorScheme.outlineVariant;
  }
}
