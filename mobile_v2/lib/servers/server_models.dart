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

/// An active connection of a server (subset of `GET /api/connections`).
class ServerSessionInfo {
  const ServerSessionInfo({
    required this.id,
    required this.serverId,
    required this.kind,
    required this.openedAt,
  });

  final String id;
  final int serverId;
  final String kind;
  final DateTime openedAt;
}

/// "09.10. 14:32" — no intl dependency needed for the skeleton.
String formatOpenedAt(DateTime dt) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.day)}.${two(dt.month)}. ${two(dt.hour)}:${two(dt.minute)}';
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
/// Collect all `type == 'server'` leaves of a `GET /api/entries/list`
/// tree (folders/organizations nest via `entries`), preserving API order.
/// Corrupt nodes are skipped so one bad entry never kills the list.
List<ServerEntry> flattenServerEntries(List<dynamic> nodes) {
  final out = <ServerEntry>[];
  void walk(dynamic node) {
    if (node is Map) {
      final map = Map<String, dynamic>.from(node);
      if (map['type'] == 'server') {
        try {
          out.add(ServerEntry.fromJson(map));
        } catch (_) {
          // Skip corrupt entries.
        }
      }
      final children = map['entries'];
      if (children is List) {
        for (final child in children) {
          walk(child);
        }
      }
    }
  }

  for (final node in nodes) {
    walk(node);
  }
  return out;
}
