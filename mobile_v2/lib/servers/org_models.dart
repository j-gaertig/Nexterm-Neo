/// An organization membership (`GET /api/organizations/`).
class OrgRef {
  const OrgRef({required this.id, required this.name});

  final int id;
  final String name;

  factory OrgRef.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse('$rawId');
    if (id == null) {
      throw FormatException('Organization without id: $json');
    }
    return OrgRef(
      id: id,
      name: json['name'] as String? ?? 'Organization',
    );
  }
}

/// Load memberships, swallowing errors (org features are optional).
Future<List<OrgRef>> loadOrgRefs(
    Future<List<Map<String, dynamic>>> Function() fetch) async {
  try {
    final raw = await fetch();
    final out = <OrgRef>[];
    for (final m in raw) {
      try {
        out.add(OrgRef.fromJson(m));
      } catch (_) {}
    }
    return out;
  } catch (_) {
    return const [];
  }
}
