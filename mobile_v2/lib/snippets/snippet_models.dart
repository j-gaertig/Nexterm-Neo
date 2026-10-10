/// A reusable command snippet (`GET /api/snippets/all`).
/// Server field name is `command` (`server/validations/snippet.js`).
class Snippet {
  const Snippet({
    required this.id,
    required this.name,
    required this.command,
    this.description,
    this.organizationId,
    this.osFilter = const [],
  });

  final int id;
  final String name;
  final String command;
  final String? description;
  final int? organizationId;

  /// OS filter (`server/validations/snippet.js`).
  final List<String> osFilter;

  factory Snippet.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse('$rawId');
    if (id == null) {
      throw FormatException('Snippet without numeric id: $json');
    }
    final rawOrg = json['organizationId'];
    final rawFilter = json['osFilter'];
    return Snippet(
      id: id,
      name: json['name'] as String? ?? 'Snippet',
      command: json['command'] as String? ?? '',
      description: json['description'] as String?,
      organizationId:
          rawOrg == null ? null : int.tryParse('$rawOrg'),
      osFilter: rawFilter is List
          ? rawFilter.whereType<String>().toList()
          : const [],
    );
  }
}

/// A script library entry (`GET /api/scripts/`).
class ScriptEntry {
  const ScriptEntry(
      {required this.id,
      required this.name,
      this.content,
      this.description,
      this.osFilter = const []});

  final int id;
  final String name;

  /// Only present on detail (`GET /api/scripts/:id`) / edit flows.
  final String? content;
  final String? description;

  /// OS filter (`server/validations/script.js`).
  final List<String> osFilter;

  factory ScriptEntry.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse('$rawId');
    if (id == null) {
      throw FormatException('Script without numeric id: $json');
    }
    final rawFilter = json['osFilter'];
    return ScriptEntry(
      id: id,
      name: json['name'] as String? ?? 'Script',
      content: json['content'] as String?,
      description: json['description'] as String?,
      osFilter: rawFilter is List
          ? rawFilter.whereType<String>().toList()
          : const [],
    );
  }
}
