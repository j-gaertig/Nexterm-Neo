import 'dart:async';

import 'package:web_socket_channel/io.dart';

import '../utils/api_client.dart';

/// Small wrapper around the script WebSocket. Centralizes the connect
/// timeout and keep-alive ping (a half-open TCP connection would otherwise
/// leave a script waiting for input forever) and guards writes after close.
class ScriptConnection {
  ScriptConnection._(this.channel);

  factory ScriptConnection.open({
    required String token,
    required dynamic entryId,
    required String sessionId,
    int? identityId,
  }) {
    final queryParams = <String, String>{
      'sessionToken': token,
      'entryId': entryId.toString(),
      'sessionId': sessionId,
      if (identityId != null) 'identityId': identityId.toString(),
    };
    return ScriptConnection._(
      IOWebSocketChannel.connect(
        Uri.parse(
          ApiClient.buildWebSocketUrl('/ws/term', queryParams: queryParams),
        ),
        headers: {'User-Agent': ApiClient.userAgent},
        pingInterval: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 15),
      ),
    );
  }

  final IOWebSocketChannel channel;

  bool _ready = false;
  bool _closed = false;
  Future<void>? _closeFuture;

  Stream<dynamic> get stream => channel.stream;
  bool get isReady => _ready && !_closed;
  bool get isClosed => _closed;
  int? get closeCode => channel.closeCode;
  String? get closeReason => channel.closeReason;

  Future<void> markReady() async {
    await channel.ready;
    if (!_closed) _ready = true;
  }

  /// Returns `false` when the socket is not ready or the sink has failed.
  /// Callers must not assume a control message was delivered.
  bool send(String payload) {
    if (!_ready || _closed) return false;
    try {
      channel.sink.add(payload);
      return true;
    } catch (_) {
      _closed = true;
      return false;
    }
  }

  void markClosed() {
    _ready = false;
    _closed = true;
  }

  Future<void> close() {
    _ready = false;
    _closed = true;
    return _closeFuture ??= _close();
  }

  Future<void> _close() async {
    try {
      await channel.sink.close();
    } catch (_) {
      // The socket may already be gone.
    }
  }
}
