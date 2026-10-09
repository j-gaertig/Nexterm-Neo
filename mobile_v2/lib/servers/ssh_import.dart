/// Parse OpenSSH client config text into import payload hosts
/// (web SSHConfigImportDialog equivalent, minus key-file upload).
///
/// Understands `Host` (skips `*`/wildcards), `HostName`, `Port`,
/// `User` (kept as username hint). Returns one map per host:
/// `{name, ip, port, config, identities}`.
List<Map<String, dynamic>> parseSshConfig(String text) {
  final hosts = <Map<String, dynamic>>[];
  Map<String, dynamic>? current;
  Object? currentUser;
  String? asString(Object? v) =>
      v == null ? null : '$v'.trim().isEmpty ? null : '$v'.trim();

  void push() {
    final host = current;
    if (host == null) return;
    final name = asString(host['name']);
    final ip = asString(host['hostname']) ?? name;
    if (name == null || name.isEmpty || ip == null) return;
    final entry = <String, dynamic>{
      'name': name,
      'ip': ip,
      'port': host['port'] ?? 22,
      'config': <String, dynamic>{},
      'identities': <int>[],
    };
    final user = currentUser;
    if (user != null) entry['username'] = user;
    hosts.add(entry);
  }

  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final hostMatch =
        RegExp(r'^Host\s+(.+)$', caseSensitive: false)
            .firstMatch(line);
    if (hostMatch != null) {
      push();
      final pattern = hostMatch.group(1)!.trim();
      currentUser = null;
      current = (pattern == '*' || pattern.contains('*'))
          ? null
          : {'name': pattern, 'hostname': pattern, 'port': 22};
      continue;
    }
    if (current == null) continue;
    final kv = RegExp(r'^(\w+)\s+(.+)$').firstMatch(line);
    if (kv == null) continue;
    final key = kv.group(1)!.toLowerCase();
    final value = kv.group(2)!.trim();
    switch (key) {
      case 'hostname':
        current['hostname'] = value;
      case 'port':
        current['port'] = int.tryParse(value) ?? 22;
      case 'user':
        currentUser = value;
    }
  }
  push();
  return hosts
      .map((h) => {
            'name': h['name'],
            'ip': h['ip'],
            'port': h['port'],
            'config': h['config'],
            'identities': h['identities'],
          })
      .toList();
}
