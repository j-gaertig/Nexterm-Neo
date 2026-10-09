// SFTP channel protocol: op codes, frame codec, entry model,
// path helpers and REST transfer URIs.
//
// Wire format (see `server/routes/sftpWS.js`): every WebSocket frame is
// binary, first byte = op code, remaining bytes = UTF-8 JSON payload.
// Acknowledgements for mutating ops are a single op byte without payload.
//
// REST transfers (see `server/routes/sftp.js`) authenticate via query
// token (`sessionToken`), never via Bearer header.
import 'dart:convert';
import 'dart:typed_data';

/// Op codes mirrored from `server/routes/sftpWS.js` (`OP` table).
/// Only the ops used by the mobile client are listed here.
abstract final class SftpOp {
  static const int ready = 0x0;
  static const int listFiles = 0x1;
  static const int createFile = 0x4;
  static const int createFolder = 0x5;
  static const int deleteFile = 0x6;
  static const int deleteFolder = 0x7;
  static const int renameFile = 0x8;
  static const int error = 0x9;
  static const int pathSync = 0x12;
}

/// Encode one outbound frame: op byte + UTF-8 JSON payload.
Uint8List encodeSftpMessage(int op, [Map<String, dynamic>? payload]) {
  final List<int> body =
      payload == null ? const [] : utf8.encode(json.encode(payload));
  final out = Uint8List(1 + body.length);
  out[0] = op;
  if (body.isNotEmpty) out.setRange(1, out.length, body);
  return out;
}

/// A decoded inbound frame.
class SftpMessage {
  const SftpMessage({required this.op, this.payload = const {}, this.raw = ''});

  final int op;
  final Map<String, dynamic> payload;
  final String raw;
}

/// Decode an inbound WebSocket frame (`Uint8List`, `List<int>` or `String`).
/// Returns null for empty or unusable frames.
SftpMessage? decodeSftpMessage(dynamic data) {
  final Uint8List bytes;
  if (data is Uint8List) {
    bytes = data;
  } else if (data is List<int>) {
    bytes = Uint8List.fromList(data);
  } else if (data is String) {
    bytes = Uint8List.fromList(utf8.encode(data));
  } else {
    return null;
  }
  if (bytes.isEmpty) return null;
  final op = bytes[0];
  if (bytes.length == 1) return SftpMessage(op: op);
  String text;
  try {
    text = utf8.decode(bytes.sublist(1));
  } catch (_) {
    return SftpMessage(op: op);
  }
  try {
    final decoded = json.decode(text);
    if (decoded is Map<String, dynamic>) {
      return SftpMessage(op: op, payload: decoded, raw: text);
    }
    if (decoded is Map) {
      return SftpMessage(
          op: op, payload: Map<String, dynamic>.from(decoded), raw: text);
    }
  } catch (_) {
    // Fall through to a payload-less message with the raw text.
  }
  return SftpMessage(op: op, raw: text);
}

/// Human readable message of an `ERROR` frame.
String sftpErrorMessage(SftpMessage message,
    [String fallback = 'Operation failed.']) {
  final Object? detail =
      message.payload['message'] ?? message.payload['error'];
  if (detail is String && detail.isNotEmpty) return detail;
  if (message.raw.isNotEmpty) return message.raw;
  return fallback;
}

/// One directory entry of a `LIST_FILES` response.
class SftpEntry {
  const SftpEntry({
    required this.name,
    required this.isDir,
    this.isSymlink = false,
    this.size = 0,
    this.mtime = 0,
    this.mode = 0,
  });

  final String name;
  final bool isDir;
  final bool isSymlink;
  final int size;

  /// Last modification time, seconds since epoch (`last_modified`).
  final int mtime;
  final int mode;

  /// Parse one item of the `files` array (`{name, type, isSymlink,
  /// last_modified, size, mode}`, see `EngineSftpClient` DirList).
  factory SftpEntry.fromJson(Map<String, dynamic> json) => SftpEntry(
        name: json['name'] as String? ?? '',
        isDir: json['type'] == 'folder' || json['isDir'] == true,
        isSymlink: json['isSymlink'] == true,
        size: (json['size'] as num?)?.toInt() ?? 0,
        mtime: (json['last_modified'] as num?)?.toInt() ??
            (json['mtime'] as num?)?.toInt() ??
            0,
        mode: (json['mode'] as num?)?.toInt() ?? 0,
      );

  String get formattedSize {
    if (isDir) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Parse the `files` array of a `LIST_FILES` payload (empty on bad shape).
List<SftpEntry> parseSftpListing(Map<String, dynamic> payload) {
  final Object? files = payload['files'];
  if (files is! List) return const [];
  final entries = <SftpEntry>[];
  for (final item in files) {
    if (item is Map<String, dynamic>) {
      entries.add(SftpEntry.fromJson(item));
    } else if (item is Map) {
      entries.add(SftpEntry.fromJson(Map<String, dynamic>.from(item)));
    }
  }
  return entries;
}

/// Folders first, then case-insensitive by name. Returns a new list.
List<SftpEntry> sortSftpEntries(List<SftpEntry> entries) {
  final sorted = List<SftpEntry>.of(entries);
  sorted.sort((a, b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return sorted;
}

/// Join a directory path and an entry name.
String sftpJoin(String base, String name) =>
    base.endsWith('/') ? '$base$name' : '$base/$name';

bool _isRootPath(String path) =>
    path == '/' || RegExp(r'^[A-Za-z]:/$').hasMatch(path);

/// Parent directory; the root maps to itself.
String sftpParent(String path) {
  if (_isRootPath(path)) return path;
  final clean =
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  final idx = clean.lastIndexOf('/');
  if (idx <= 0) return '/';
  final parent = clean.substring(0, idx);
  if (RegExp(r'^[A-Za-z]:$').hasMatch(parent)) return '$parent/';
  return parent;
}

/// Last segment of a path ('' for the root).
String sftpBasename(String path) {
  if (_isRootPath(path)) return '';
  final clean =
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  final idx = clean.lastIndexOf('/');
  return idx < 0 ? clean : clean.substring(idx + 1);
}

/// Non-empty segments of a path (`/a/b/` -> `[a, b]`).
List<String> sftpSegments(String path) =>
    path.split('/').where((s) => s.isNotEmpty).toList();

/// Absolute path from segments (`[]` -> `/`).
String sftpFromSegments(List<String> segments) =>
    segments.isEmpty ? '/' : '/${segments.join('/')}';

/// True when [path] is [root] or below it (`/` contains everything).
bool sftpIsWithin(String path, String root) {
  if (root.isEmpty || root == '/') return true;
  final clean =
      root.endsWith('/') && root.length > 1 ? root.substring(0, root.length - 1) : root;
  if (RegExp(r'^[A-Za-z]:$').hasMatch(clean)) {
    return path == clean ||
        path == '$clean/' ||
        path.startsWith('$clean/');
  }
  return path == clean || path.startsWith('$clean/');
}

Uri _sftpRestUri(
  String baseUrl,
  String endpoint,
  String sessionToken,
  String sessionId,
  String remotePath,
) {
  final base = Uri.parse(baseUrl);
  return base.replace(
    path: '${base.path}$endpoint',
    queryParameters: {
      ...base.queryParameters,
      'sessionToken': sessionToken,
      'sessionId': sessionId,
      'path': remotePath,
    },
  );
}

/// `POST /api/entries/sftp/upload?...` — raw bytes body.
Uri sftpUploadUri(
  String baseUrl,
  String sessionToken,
  String sessionId,
  String remotePath,
) =>
    _sftpRestUri(
        baseUrl, '/entries/sftp/upload', sessionToken, sessionId, remotePath);

/// `GET /api/entries/sftp?...` — file bytes, or a ZIP for folders.
Uri sftpDownloadUri(
  String baseUrl,
  String sessionToken,
  String sessionId,
  String remotePath,
) =>
    _sftpRestUri(baseUrl, '/entries/sftp', sessionToken, sessionId, remotePath);
