/// Server list models for the servers page (UI-only shapes).
///
/// NOTE: these are NOT the API shapes. When wiring the API
/// (TODO below), map `GET /api/entries/list` entries via
/// `config.ip`/`config.port`/`config.protocol`, and
/// `GET /api/connections` items via
/// `sessionId`/`entryId`/`configuration.type` (see `mobile_v2/API.md`).
library;

/// A server entry (`type == 'server'` leaf of `GET /api/entries/list`).
class ServerEntry {
  const ServerEntry({
    required this.id,
    required this.name,
    required this.ip,
    this.port,
    this.protocol,
    this.icon,
    this.status,
    this.macAddress,
    this.wakeOnLanEnabled = false,
    this.identities = const [],
  });

  final int id;
  final String name;
  final String ip;
  final int? port;
  final String? protocol;
  final String? icon;
  final String? status;
  final String? macAddress;
  final bool wakeOnLanEnabled;
  final List<int> identities;

  /// Parse a `type == 'server'` node of `GET /api/entries/list`
  /// (`server/controllers/entry.js` `buildEntryObject`).
  /// Throws [FormatException] on corrupt nodes — callers skip those.
  factory ServerEntry.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse('$rawId');
    if (id == null) {
      throw FormatException('Server entry without numeric id: $json');
    }
    // NOTE: the list response carries no `port` (dropped server-side);
    // read defensively in case it appears (top-level or nested config).
    final config = json['config'];
    final rawPort =
        json['port'] ?? (config is Map ? config['port'] : null);
    final port = rawPort is num
        ? rawPort.toInt()
        : int.tryParse('$rawPort');
    final identities = json['identities'];
    return ServerEntry(
      id: id,
      name: json['name'] as String? ?? 'Server',
      ip: json['ip'] as String? ?? '',
      port: port,
      protocol: json['protocol'] as String?,
      icon: json['icon'] as String?,
      status: json['status'] as String?,
      macAddress: json['macAddress'] as String?,
      wakeOnLanEnabled: json['wakeOnLanEnabled'] == true,
      identities: identities is List
          ? identities
              .whereType<num>()
              .map((e) => e.toInt())
              .toList()
          : const [],
    );
  }

  /// "192.168.1.10", "192.168.1.10:2222" or '' when unknown.
  String get address {
    if (ip.isEmpty) return port == null ? '' : ':${port!}';
    return port == null ? ip : '$ip:$port';
  }

  /// Primary connect protocol: ssh or rdp (format helper for the sheet).
  String get primaryProtocol {
    final p = (protocol ?? '').toLowerCase();
    if (p == 'rdp') return 'rdp';
    return 'ssh';
  }
}

/// Subtitle for list + sheet headers: "ip • SSH", "SSH" or "No address".
String formatServerSubtitle(ServerEntry entry) {
  final parts = <String>[
    if (entry.address.isNotEmpty) entry.address,
    (entry.protocol ?? 'ssh').toUpperCase(),
  ];
  if (parts.length == 1 && entry.address.isEmpty) return 'No address';
  return parts.join(' • ');
}
/// Tree node of `GET /api/entries/list` (folders nest via `entries`).
sealed class EntryNode {
  const EntryNode();
}

/// A `type == 'server'` leaf.
class ServerNode extends EntryNode {
  const ServerNode(this.entry);

  final ServerEntry entry;
}

/// A `type == 'folder'` or `type == 'organization'` branch.
class FolderNode extends EntryNode {
  const FolderNode(
      {required this.id,
      required this.name,
      this.children = const [],
      this.isOrganization = false});

  final String id;
  final String name;
  final List<EntryNode> children;
  final bool isOrganization;
}

/// Parse a `GET /api/entries/list` tree, preserving folders.
/// Folders without visible servers are pruned; `pve-*` nodes are skipped
/// (they get their own place later).
List<EntryNode> parseEntryTree(List<dynamic> nodes) {
  List<EntryNode>? parseNodes(List<dynamic> items) {
    final out = <EntryNode>[];
    for (final item in items) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final type = map['type'] as String?;
      if (type == 'server') {
        try {
          out.add(ServerNode(ServerEntry.fromJson(map)));
        } catch (_) {
          // Skip corrupt entries.
        }
      } else if (type == 'folder' || type == 'organization') {
        final children = map['entries'];
        final parsed =
            children is List ? parseNodes(children) : null;
        if (parsed != null && parsed.isNotEmpty) {
          out.add(FolderNode(
            id: '${map['id']}',
            name: map['name'] as String? ?? 'Folder',
            children: parsed,
            isOrganization: type == 'organization',
          ));
        }
      }
    }
    return out;
  }

  return parseNodes(nodes) ?? const [];
}

/// Collect all servers of a parsed tree, preserving order.
List<ServerEntry> flattenNodes(List<EntryNode> nodes) {
  final out = <ServerEntry>[];
  void walk(EntryNode node) {
    switch (node) {
      case ServerNode(:final entry):
        out.add(entry);
      case FolderNode(:final children):
        for (final child in children) {
          walk(child);
        }
    }
  }

  for (final node in nodes) {
    walk(node);
  }
  return out;
}
