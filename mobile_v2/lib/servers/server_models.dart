/// Server list models for the servers page (UI-only shapes).
///
/// NOTE: these are NOT the API shapes. When wiring the API
/// (TODO below), map `GET /api/entries/list` entries via
/// `config.ip`/`config.port`/`config.protocol`, and
/// `GET /api/connections` items via
/// `sessionId`/`entryId`/`configuration.type` (see `mobile_v2/API.md`).
library;

/// A server entry (subset of the API entry model).
class ServerEntry {
  const ServerEntry({
    required this.id,
    required this.name,
    required this.ip,
    this.port,
    this.protocol,
    this.icon,
  });

  final int id;
  final String name;
  final String ip;
  final int? port;
  final String? protocol;
  final String? icon;

  /// "192.168.1.10" or "192.168.1.10:2222".
  String get address => port == null ? ip : '$ip:$port';

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

/// Demo entries for UI iteration (TODO: API wiring).
const List<ServerEntry> demoServers = [
  ServerEntry(
      id: 1, name: 'Webserver', ip: '192.168.1.10', port: 22, protocol: 'ssh'),
  ServerEntry(
      id: 2, name: 'Windows Box', ip: '192.168.1.20', protocol: 'rdp'),
  ServerEntry(
      id: 3, name: 'NAS', ip: '192.168.1.30', port: 2222, protocol: 'ssh'),
];

/// Demo sessions for UI iteration (TODO: API wiring).
List<ServerSessionInfo> demoSessions(int serverId) {
  final now = DateTime.now();
  return switch (serverId) {
    1 => [
        ServerSessionInfo(
            id: 's1', serverId: 1, kind: 'ssh', openedAt: now.subtract(const Duration(hours: 2, minutes: 14))),
        ServerSessionInfo(
            id: 's2', serverId: 1, kind: 'sftp', openedAt: now.subtract(const Duration(minutes: 47))),
        ServerSessionInfo(
            id: 's3', serverId: 1, kind: 'ssh', openedAt: now.subtract(const Duration(minutes: 5))),
      ],
    2 => [
        ServerSessionInfo(
            id: 's4', serverId: 2, kind: 'rdp', openedAt: now.subtract(const Duration(hours: 5, minutes: 2))),
      ],
    _ => [],
  };
}
