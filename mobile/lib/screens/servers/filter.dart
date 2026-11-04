part of '../servers_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ServersFilter on ServersScreenState {
  List<Tag> _collectTags(List<dynamic> list) {
    final map = <int, Tag>{};
    for (final item in list) {
      if (item is Server) {
        for (final t in item.tags ?? <Tag>[]) {
          map[t.id] = t;
        }
      } else if (item is ServerFolder) {
        for (final s in item.allServers) {
          for (final t in s.tags ?? <Tag>[]) {
            map[t.id] = t;
          }
        }
        for (final t in _collectTags(item.allFolders)) {
          map[t.id] = t;
        }
      }
    }
    return map.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  bool _serverMatchesTags(Server s) =>
      _selectedTags.isEmpty ||
      (s.tags?.any((t) => _selectedTags.contains(t.id)) ?? false);

  void _filterFolders() {
    if (_query.trim().isEmpty && _selectedTags.isEmpty) {
      filteredFolders = List.from(folders);
      return;
    }
    filteredFolders = folders
        .map((item) {
          if (item is ServerFolder) return _filterFolder(item);
          if (item is Server) return _serverMatches(item) ? item : null;
          return null;
        })
        .where((e) => e != null)
        .toList();
  }

  bool _serverMatches(Server s) {
    final matchesTag = _serverMatchesTags(s);
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return matchesTag;
    return matchesTag &&
        (s.name.toLowerCase().contains(q) || s.ip.toLowerCase().contains(q));
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
      id: folder.id,
      name: folder.name,
      type: folder.type,
      position: folder.position,
      organizationId: folder.organizationId,
      requireConnectionReason: folder.requireConnectionReason,
      entries: kept,
      ip: folder.ip,
      icon: folder.icon,
      folderType: folder.folderType,
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
          id: folder.id,
          name: folder.name,
          type: folder.type,
          position: folder.position,
          organizationId: folder.organizationId,
          requireConnectionReason: folder.requireConnectionReason,
          entries: tagEntries,
          ip: folder.ip,
          icon: folder.icon,
          folderType: folder.folderType,
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
        id: folder.id,
        name: folder.name,
        type: folder.type,
        position: folder.position,
        organizationId: folder.organizationId,
        requireConnectionReason: folder.requireConnectionReason,
        entries: kept,
        ip: folder.ip,
        icon: folder.icon,
        folderType: folder.folderType,
      );
    }
    return null;
  }
}
