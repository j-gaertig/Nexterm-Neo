/// A login identity / credential reference (no secrets, mirrors
/// `GET /api/identities/list`).
class Identity {
  const Identity(
      {required this.id,
      required this.name,
      required this.type,
      this.username});

  final int id;
  final String name;
  final String type;
  final String? username;

  factory Identity.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
    if (id == null) throw FormatException('Identity without id: $json');
    return Identity(
      id: id,
      name: json['name'] as String? ?? 'Identity',
      type: json['type'] as String? ?? 'password',
      username: json['username'] as String?,
    );
  }
}

/// An active remote connection (`GET /api/connections` item, defensive).
class ConnectionInfo {
  const ConnectionInfo({
    required this.sessionId,
    required this.entryId,
    this.kind,
    this.renderer,
    this.hibernated = false,
    this.connectionReason,
  });

  final String sessionId;
  final int entryId;
  final String? kind;
  final String? renderer;
  final bool hibernated;
  final String? connectionReason;

  factory ConnectionInfo.fromJson(Map<String, dynamic> json) {
    final configuration = json['configuration'];
    final config = configuration is Map
        ? Map<String, dynamic>.from(configuration)
        : <String, dynamic>{};
    final rawEntry = json['entryId'];
    return ConnectionInfo(
      sessionId: json['sessionId'] as String? ?? '',
      entryId: rawEntry is num
          ? rawEntry.toInt()
          : int.tryParse('$rawEntry') ?? -1,
      kind: config['type'] as String?,
      renderer: config['renderer'] as String?,
      hibernated: json['isHibernated'] == true,
      connectionReason: json['connectionReason'] as String?,
    );
  }
}
