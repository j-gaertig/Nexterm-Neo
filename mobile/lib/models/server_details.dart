import 'dart:convert';

class ServerDetails {
  final dynamic id;
  final String name;
  final String? icon;
  final String type;
  final Map<String, dynamic> config;
  final List<int> identities;
  final dynamic folderId;
  final dynamic organizationId;

  const ServerDetails({
    this.id,
    this.name = '',
    this.icon,
    this.type = 'server',
    this.config = const {},
    this.identities = const [],
    this.folderId,
    this.organizationId,
  });

  String? get protocol => config['protocol']?.toString();

  factory ServerDetails.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> config = {};
    final rawConfig = json['config'];
    if (rawConfig is Map<String, dynamic>) {
      config = Map<String, dynamic>.from(rawConfig);
    } else if (rawConfig is Map) {
      config = Map<String, dynamic>.from(rawConfig);
    } else if (rawConfig is String && rawConfig.isNotEmpty) {
      try {
        final decoded = const JsonDecoder().convert(rawConfig);
        if (decoded is Map<String, dynamic>) config = decoded;
      } catch (_) {}
    }
    List<int> identities = [];
    final rawIds = json['identities'];
    if (rawIds is List) {
      for (final e in rawIds) {
        if (e is int) {
          identities.add(e);
        } else if (e is num && e % 1 == 0) {
          identities.add(e.toInt());
        } else if (e is! num) {
          final parsed = int.tryParse(e.toString());
          if (parsed != null) identities.add(parsed);
        }
      }
    }
    dynamic folderId = json['folderId'];
    if (folderId is Map && folderId['id'] != null) folderId = folderId['id'];
    dynamic organizationId = json['organizationId'];
    if (organizationId is Map && organizationId['id'] != null) organizationId = organizationId['id'];
    return ServerDetails(
      id: json['id'],
      name: (json['name'] ?? '').toString(),
      icon: json['icon']?.toString(),
      type: (json['type'] ?? 'server').toString(),
      config: config,
      identities: identities,
      folderId: folderId,
      organizationId: organizationId,
    );
  }

}

class EngineInfo {
  final dynamic id;
  final String name;
  final bool connected;

  const EngineInfo({this.id, this.name = '', this.connected = false});

  factory EngineInfo.fromJson(Map<String, dynamic> json) => EngineInfo(
        id: json['id'],
        name: (json['name'] ?? '').toString(),
        connected: json['connected'] == true,
      );
}


