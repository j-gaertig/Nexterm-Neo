// Live SFTP channel over WebSocket plus REST up/download transfers.
//
// The browse protocol frames are defined in `sftp_protocol.dart`;
// the endpoints mirror `server/routes/sftpWS.js` (WS) and
// `server/routes/sftp.js` (REST, query-token auth).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'sftp_protocol.dart';

/// A connected `/ws/sftp` channel. Inbound frames are decoded to
/// [SftpMessage] and exposed via [messages].
class SftpConnection {
  SftpConnection._(this._channel);

  final WebSocketChannel _channel;
  final StreamController<SftpMessage> _controller =
      StreamController<SftpMessage>();
  bool _closed = false;

  /// Open the channel. Does not wait for the READY frame.
  static SftpConnection connect(String url) {
    final connection =
        SftpConnection._(WebSocketChannel.connect(Uri.parse(url)));
    connection._channel.stream.listen(
      (dynamic data) {
        final message = decodeSftpMessage(data);
        if (message != null && !connection._closed) {
          connection._controller.add(message);
        }
      },
      onError: (Object error) {
        if (!connection._closed) connection._controller.addError(error);
      },
      onDone: () {
        if (!connection._closed) connection._controller.close();
      },
    );
    return connection;
  }

  Stream<SftpMessage> get messages => _controller.stream;

  void _send(int op, [Map<String, dynamic>? payload]) {
    if (_closed) return;
    try {
      _channel.sink.add(encodeSftpMessage(op, payload));
    } catch (_) {
      // The screen surfaces channel errors via onError/onDone.
    }
  }

  void requestList(String path) =>
      _send(SftpOp.listFiles, {'path': path});

  void createFile(String path) => _send(SftpOp.createFile, {'path': path});

  void createFolder(String path) =>
      _send(SftpOp.createFolder, {'path': path});

  void deleteFile(String path) => _send(SftpOp.deleteFile, {'path': path});

  void deleteFolder(String path) =>
      _send(SftpOp.deleteFolder, {'path': path});

  void rename(String oldPath, String newPath) => _send(
      SftpOp.renameFile, {'path': oldPath, 'newPath': newPath});

  void syncPath(String path) => _send(SftpOp.pathSync, {'path': path});

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _channel.sink.close();
    } catch (_) {
      // Best effort.
    }
    try {
      await _controller.close();
    } catch (_) {
      // Already closed via onDone.
    }
  }
}

/// Thrown when a REST up/download fails.
class SftpTransferException implements Exception {
  const SftpTransferException(this.message);

  final String message;

  @override
  String toString() => 'SftpTransferException: $message';
}

String _transferError(http.Response response, String fallback) {
  try {
    final decoded = json.decode(response.body);
    if (decoded is Map) {
      final Object? detail = decoded['error'] ?? decoded['message'];
      if (detail is String && detail.isNotEmpty) return detail;
    }
  } catch (_) {
    // Fall through to the generic message.
  }
  return '$fallback (HTTP ${response.statusCode}).';
}

/// Upload raw bytes to [remotePath].
/// Throws [SftpTransferException] on failure.
Future<void> uploadSftpFile({
  required String baseUrl,
  required String sessionToken,
  required String sessionId,
  required String remotePath,
  required Uint8List bytes,
}) async {
  final uri = sftpUploadUri(baseUrl, sessionToken, sessionId, remotePath);
  late final http.Response response;
  try {
    response = await http
        .post(uri,
            headers: {'Content-Type': 'application/octet-stream'},
            body: bytes)
        .timeout(const Duration(minutes: 10));
  } on TimeoutException {
    throw const SftpTransferException('Upload timed out.');
  } catch (e) {
    throw SftpTransferException('Upload failed: $e');
  }
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw SftpTransferException(_transferError(response, 'Upload failed'));
  }
}

/// Download [remotePath] (folders arrive as ZIP, server-side).
/// Throws [SftpTransferException] on failure.
Future<Uint8List> downloadSftpFile({
  required String baseUrl,
  required String sessionToken,
  required String sessionId,
  required String remotePath,
}) async {
  final uri = sftpDownloadUri(baseUrl, sessionToken, sessionId, remotePath);
  late final http.Response response;
  try {
    response =
        await http.get(uri).timeout(const Duration(minutes: 10));
  } on TimeoutException {
    throw const SftpTransferException('Download timed out.');
  } catch (e) {
    throw SftpTransferException('Download failed: $e');
  }
  if (response.statusCode != 200) {
    throw SftpTransferException(_transferError(response, 'Download failed'));
  }
  return response.bodyBytes;
}

/// Log transfer errors without crashing (best-effort disconnect path).
void logSftpTransferError(Object error) {
  debugPrint('SFTP transfer cleanup failed: $error');
}
