// Script model, mirroring the server `Script` model (`server/models/Script.js`).
// Scripts are managed in the web client; the mobile app only consumes them
// for execution (see `docs/plans/mobile-scripts-support.md`).
import 'dart:convert';

/// OS options as offered by the web script dialog (`client/src/common/utils/osUtils.js`).
const scriptOsOptions = <String>[
  'Windows',
  'Ubuntu',
  'Debian',
  'Alpine Linux',
  'Fedora',
  'CentOS',
  'Red Hat',
  'Rocky Linux',
  'AlmaLinux',
  'openSUSE',
  'Arch Linux',
  'Manjaro',
  'Gentoo',
  'NixOS',
  'Proxmox VE',
];

/// Ports `parseOsFilter` from the web client: accepts a JSON string or a list.
List<String> parseOsFilter(dynamic osFilter) {
  if (osFilter == null) return [];
  if (osFilter is List) return osFilter.map((e) => e.toString()).toList();
  if (osFilter is String) {
    if (osFilter.isEmpty) return [];
    try {
      final parsed = const JsonDecoder().convert(osFilter);
      if (parsed is List) return parsed.map((e) => e.toString()).toList();
    } catch (_) {}
  }
  return [];
}

/// Ports `normalizeOsName` from the web client (`osUtils.js`).
String? normalizeOsName(String? osName) {
  if (osName == null) return null;
  final lower = osName.toLowerCase();
  const mappings = <List<String>>[
    ['windows', 'Windows'],
    ['microsoft windows', 'Windows'],
    ['ubuntu', 'Ubuntu'],
    ['debian', 'Debian'],
    ['alpine', 'Alpine Linux'],
    ['fedora', 'Fedora'],
    ['centos', 'CentOS'],
    ['red hat', 'Red Hat'],
    ['rhel', 'Red Hat'],
    ['rocky', 'Rocky Linux'],
    ['alma', 'AlmaLinux'],
    ['opensuse', 'openSUSE'],
    ['suse', 'openSUSE'],
    ['arch', 'Arch Linux'],
    ['manjaro', 'Manjaro'],
    ['gentoo', 'Gentoo'],
    ['nixos', 'NixOS'],
    ['proxmox', 'Proxmox VE'],
  ];
  for (final entry in mappings) {
    if (lower.contains(entry[0])) return entry[1];
  }
  return osName;
}

/// Best-effort OS detection from the icon name used by the server editor.
/// Monitoring snapshots are authoritative; this only covers the window before
/// the first snapshot exists or when monitoring is unavailable.
String? normalizeOsNameFromIcon(String? icon) {
  if (icon == null || icon.trim().isEmpty) return null;
  final lower = icon.toLowerCase();
  const mappings = <List<String>>[
    ['windows', 'Windows'],
    ['ubuntu', 'Ubuntu'],
    ['debian', 'Debian'],
    ['alpine', 'Alpine Linux'],
    ['fedora', 'Fedora'],
    ['centos', 'CentOS'],
    ['redhat', 'Red Hat'],
    ['red-hat', 'Red Hat'],
    ['rhel', 'Red Hat'],
    ['rocky', 'Rocky Linux'],
    ['alma', 'AlmaLinux'],
    ['opensuse', 'openSUSE'],
    ['suse', 'openSUSE'],
    ['manjaro', 'Manjaro'],
    ['gentoo', 'Gentoo'],
    ['nixos', 'NixOS'],
    ['proxmox', 'Proxmox VE'],
    ['arch', 'Arch Linux'],
  ];
  for (final entry in mappings) {
    if (lower.contains(entry[0])) return entry[1];
  }
  return null;
}

/// Ports `matchesOsFilter` from the web client (`osUtils.js`).
bool matchesOsFilter(
  List<String> filter,
  String? serverOsName, {
  required bool isPveEntry,
}) {
  final normalized = filter.map(normalizeOsName).whereType<String>().toList();
  final hasPveFilter = normalized.contains('Proxmox VE');
  final isOnlyPve = normalized.length == 1 && hasPveFilter;

  if (isPveEntry) {
    if (normalized.isEmpty) return true;
    return hasPveFilter;
  } else {
    if (normalized.isEmpty) return true;
    if (isOnlyPve) return false;
    if (serverOsName == null) return false;
    return normalized.contains(serverOsName);
  }
}

class Script {
  final int id;
  final String name;
  final String? description;
  final List<String> osFilter;
  final int? organizationId;
  final int? sourceId;
  final int sortOrder;

  const Script({
    required this.id,
    required this.name,
    this.description,
    this.osFilter = const [],
    this.organizationId,
    this.sourceId,
    this.sortOrder = 0,
  });

  factory Script.fromJson(Map<String, dynamic> json) => Script(
    id: json['id'] as int,
    name: (json['name'] as String?) ?? '',
    description: json['description'] as String?,
    osFilter: parseOsFilter(json['osFilter']),
    organizationId: (json['organizationId'] as num?)?.toInt(),
    sourceId: (json['sourceId'] as num?)?.toInt(),
    sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
  );

  /// Source-synced scripts are read-only and cannot be edited or deleted
  /// anywhere (the mobile app never edits scripts anyway).
  bool get isSource => sourceId != null;

  /// Hidden easter egg from the web client. Management stays in the web
  /// client; the mobile picker intentionally never offers it.
  bool get isSecret => name == '???' && description == 'What happened?';

  /// Whether the script targets Windows (PowerShell) — decided from the
  /// OS filter exactly like `ScriptLayer.start` on the server.
  bool get isWindows =>
      osFilter.any((os) => os.toLowerCase().contains('windows'));

  /// Normalized OS names for badges.
  List<String> get osBadges =>
      osFilter.map(normalizeOsName).whereType<String>().toList();

  bool matchesSearch(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        (description?.toLowerCase().contains(q) ?? false);
  }
}
