/// A reusable command snippet (`GET /api/snippets/all`).
class Snippet {
  const Snippet({
    required this.id,
    required this.name,
    required this.content,
    this.description,
    this.organizationId,
  });

  final int id;
  final String name;
  final String content;
  final String? description;
  final int? organizationId;

  factory Snippet.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawOrg = json['organizationId'];
    return Snippet(
      id: rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? 0,
      name: json['name'] as String? ?? 'Snippet',
      content: json['content'] as String? ?? '',
      description: json['description'] as String?,
      organizationId:
          rawOrg == null ? null : int.tryParse('$rawOrg'),
    );
  }
}

/// A script library entry (`GET /api/scripts/`).
class ScriptEntry {
  const ScriptEntry({required this.id, required this.name});

  final int id;
  final String name;

  factory ScriptEntry.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    return ScriptEntry(
      id: rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? 0,
      name: json['name'] as String? ?? 'Script',
    );
  }
}
