import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:guacamole_common_dart/guacamole_common_dart.dart';
import 'package:web_socket_channel/io.dart';
import 'package:xterm/xterm.dart';

import '../models/server.dart';
import '../utils/api_client.dart';
import 'connection_service.dart';

enum ConnectionType { guacamole, terminal, sftp }

class AppSession {
  final String sessionId;
  final Server server;
  final ConnectionType type;
  bool isConnected;
  String? error;
  String? sftpPath;
  String? sftpRootPath;

  /// Identity used for the connection (mirrors web `session.identity`).
  /// Used to prioritize the password fill hint, like the web client
  /// unshifting `session.identity` to the front of the identity list.
  int? identityId;

  /// True when the session was opened with an ad-hoc `directIdentity`
  /// (quick connect) instead of a stored identity. Reconnects must not fall
  /// back to a stored server identity in that case.
  bool usedDirectIdentity;

  GuacClient? guacClient;
  GuacWebSocketTunnel? guacTunnel;

  Terminal? terminal;
  IOWebSocketChannel? termChannel;
  StreamSubscription? termSubscription;

  IOWebSocketChannel? sftpChannel;
  StreamSubscription? sftpSubscription;

  VoidCallback? showMenu;

  VoidCallback? showSnippets;

  VoidCallback? showAI;

  VoidCallback? onCallbacksReady;

  AppSession({
    required this.sessionId,
    required this.server,
    required this.type,
    this.isConnected = false,
    this.error,
    this.identityId,
    this.usedDirectIdentity = false,
    this.guacClient,
    this.guacTunnel,
    this.terminal,
    this.termChannel,
    this.termSubscription,
    this.sftpChannel,
    this.sftpSubscription,
  });
}

class SessionManager extends ChangeNotifier {
  final Map<String, AppSession> _sessions = {};
  String? _activeSessionId;

  List<AppSession> get sessions => _sessions.values.toList();
  int get sessionCount => _sessions.length;
  String? get activeSessionId => _activeSessionId;
  AppSession? get activeSession =>
      _activeSessionId != null ? _sessions[_activeSessionId] : null;
  AppSession? getSession(String id) => _sessions[id];
  bool get hasActiveSessions => _sessions.isNotEmpty;

  Future<AppSession> createGuacSession({
    required String token,
    required Server server,
    Map<String, dynamic>? directIdentity,
    String? connectionReason,
  }) async {
    final identityId = directIdentity != null
        ? null
        : (server.identities?.isNotEmpty == true ? server.identities!.first : null);

    final cs = await ConnectionService.createSession(
      token: token,
      entryId: server.id is int ? server.id : int.parse(server.id.toString()),
      identityId: identityId ?? 0,
      directIdentity: directIdentity,
      connectionReason: connectionReason,
    );

    final tunnel = GuacWebSocketTunnel(ApiClient.buildWebSocketUrl('/ws/guac/'));
    final client = GuacClient(tunnel);

    final session = AppSession(
      sessionId: cs.sessionId,
      server: server,
      type: ConnectionType.guacamole,
      guacClient: client,
      guacTunnel: tunnel,
    );

    _sessions[session.sessionId] = session;
    _activeSessionId = session.sessionId;
    notifyListeners();
    return session;
  }

  Future<AppSession> createTerminalSession({
    required String token,
    required Server server,
    Map<String, dynamic>? directIdentity,
    String? connectionReason,
    String? startPath,
  }) async {
    final identityId = directIdentity != null
        ? null
        : (server.identities?.isNotEmpty == true ? server.identities!.first : null);

    final cs = await ConnectionService.createSession(
      token: token,
      entryId: server.id is int ? server.id : int.parse(server.id.toString()),
      identityId: identityId ?? 0,
      directIdentity: directIdentity,
      connectionReason: connectionReason,
      startPath: startPath,
    );

    final terminal = Terminal(maxLines: 10000);

    final queryParams = <String, String>{
      'sessionToken': token,
      'entryId': server.id.toString(),
      'sessionId': cs.sessionId,
      if (identityId != null) 'identityId': identityId.toString(),
    };

    final channel = IOWebSocketChannel.connect(
      Uri.parse(ApiClient.buildWebSocketUrl('/ws/term', queryParams: queryParams)),
      headers: {'User-Agent': ApiClient.userAgent},
    );

    final session = AppSession(
      sessionId: cs.sessionId,
      server: server,
      type: ConnectionType.terminal,
      terminal: terminal,
      termChannel: channel,
      identityId: identityId,
      usedDirectIdentity: directIdentity != null,
    );

    _sessions[session.sessionId] = session;
    _activeSessionId = session.sessionId;
    notifyListeners();
    return session;
  }

  Future<AppSession> createSftpSession({
    required String token,
    required Server server,
    Map<String, dynamic>? directIdentity,
    String? connectionReason,
  }) async {
    final identityId = directIdentity != null
        ? null
        : (server.identities?.isNotEmpty == true ? server.identities!.first : null);

    final cs = await ConnectionService.createSession(
      token: token,
      entryId: server.id is int ? server.id : int.parse(server.id.toString()),
      identityId: identityId ?? 0,
      type: 'sftp',
      directIdentity: directIdentity,
      connectionReason: connectionReason,
    );

    final queryParams = <String, String>{
      'sessionToken': token,
      'sessionId': cs.sessionId,
    };

    final channel = IOWebSocketChannel.connect(
      Uri.parse(ApiClient.buildWebSocketUrl('/ws/sftp', queryParams: queryParams)),
      headers: {'User-Agent': ApiClient.userAgent},
    );

    final session = AppSession(
      sessionId: cs.sessionId,
      server: server,
      type: ConnectionType.sftp,
      sftpChannel: channel,
    );

    _sessions[session.sessionId] = session;
    _activeSessionId = session.sessionId;
    notifyListeners();
    return session;
  }

  void setActive(String sessionId) {
    if (_sessions.containsKey(sessionId)) {
      _activeSessionId = sessionId;
      notifyListeners();
    }
  }

  Future<void> restoreSessions({required String token}) async {
    try {
      final serverSessions = await ConnectionService.listSessions(token: token);
      if (serverSessions.isEmpty) return;

      final entryIds = serverSessions
          .map((s) => s['entryId'])
          .whereType<int>()
          .toSet();
      final entryMap = <int, Server>{};
      for (final eid in entryIds) {
        try {
          final resp = await ApiClient.get('/entries/$eid', token: token);
          if (resp.statusCode == 200) {
            final data = json.decode(resp.body);
            if (data is Map<String, dynamic>) {
              entryMap[eid] = Server.fromJson(data);
            }
          }
        } catch (_) {}
      }

      for (final sData in serverSessions) {
        final sessionId = sData['sessionId'] as String?;
        final entryId = sData['entryId'] as int?;
        final isHibernated = sData['isHibernated'] as bool? ?? false;
        if (sessionId == null || entryId == null) continue;

        if (_sessions.containsKey(sessionId)) continue;

        if (isHibernated) continue;

        final server = entryMap[entryId];
        if (server == null) continue;

        final config = sData['configuration'] as Map<String, dynamic>? ?? {};
        final type = _resolveConnectionType(config, server);

        try {
          switch (type) {
            case ConnectionType.guacamole:
              final tunnel = GuacWebSocketTunnel(ApiClient.buildWebSocketUrl('/ws/guac/'));
              final client = GuacClient(tunnel);
              _sessions[sessionId] = AppSession(
                sessionId: sessionId,
                server: server,
                type: ConnectionType.guacamole,
                guacClient: client,
                guacTunnel: tunnel,
              );
              break;

            case ConnectionType.terminal:
              final terminal = Terminal(maxLines: 10000);
              final identityId = config['identityId'];
              final queryParams = <String, String>{
                'sessionToken': token,
                'entryId': entryId.toString(),
                'sessionId': sessionId,
                if (identityId != null) 'identityId': identityId.toString(),
              };
              final channel = IOWebSocketChannel.connect(
                Uri.parse(ApiClient.buildWebSocketUrl('/ws/term', queryParams: queryParams)),
                headers: {'User-Agent': ApiClient.userAgent},
              );
              _sessions[sessionId] = AppSession(
                sessionId: sessionId,
                server: server,
                type: ConnectionType.terminal,
                terminal: terminal,
                termChannel: channel,
                identityId: identityId is int
                    ? identityId
                    : int.tryParse(identityId?.toString() ?? ''),
                // Known limitation: the session list strips ad-hoc
                // `directIdentity` payloads, so a restored quick-connect
                // session cannot be distinguished from a stored-identity one.
                // Reconnect then falls back to the server identity (transport
                // still resolves server-side); only hint prioritization may
                // differ until the session is recreated.
              );
              break;

            case ConnectionType.sftp:
              final queryParams = <String, String>{
                'sessionToken': token,
                'sessionId': sessionId,
              };
              final channel = IOWebSocketChannel.connect(
                Uri.parse(ApiClient.buildWebSocketUrl('/ws/sftp', queryParams: queryParams)),
                headers: {'User-Agent': ApiClient.userAgent},
              );
              _sessions[sessionId] = AppSession(
                sessionId: sessionId,
                server: server,
                type: ConnectionType.sftp,
                sftpChannel: channel,
              );
              break;
          }
        } catch (_) {
          // Skip sessions that fail to reconnect
        }
      }

      if (_sessions.isNotEmpty && _activeSessionId == null) {
        _activeSessionId = _sessions.keys.first;
      }
      notifyListeners();
    } catch (_) {
      // Silently fail — restore is best-effort
    }
  }

  ConnectionType _resolveConnectionType(Map<String, dynamic> config, Server server) {
    final cfgType = config['type'] as String?;
    final renderer = config['renderer'] as String?;
    if (cfgType == 'sftp' || renderer == 'sftp') return ConnectionType.sftp;
    final protocol = server.protocol?.toLowerCase();
    if (protocol == 'rdp' || protocol == 'vnc' || renderer == 'guac') {
      return ConnectionType.guacamole;
    }
    return ConnectionType.terminal;
  }

  void _disconnectSession(AppSession session) {
    switch (session.type) {
      case ConnectionType.guacamole:
        try { session.guacClient?.disconnect(); } catch (_) {}
        try { session.guacClient?.dispose(); } catch (_) {}
        break;
      case ConnectionType.terminal:
        try { session.termSubscription?.cancel(); } catch (_) {}
        try { session.termChannel?.sink.close(); } catch (_) {}
        session.terminal?.onOutput = null;
        session.terminal?.onResize = null;
        break;
      case ConnectionType.sftp:
        try { session.sftpSubscription?.cancel(); } catch (_) {}
        try { session.sftpChannel?.sink.close(); } catch (_) {}
        break;
    }
  }

  Future<void> closeSession(String sessionId, String token) async {
    final session = _sessions[sessionId];
    if (session == null) return;

    _disconnectSession(session);

    await ConnectionService.deleteSession(token: token, sessionId: sessionId);
    _sessions.remove(sessionId);

    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.keys.last : null;
    }
    notifyListeners();
  }

  Future<bool> reconnectTerminalSession({
    required String token,
    required AppSession session,
  }) async {
    try {
      session.termSubscription?.cancel();
      session.termSubscription = null;
      try { session.termChannel?.sink.close(); } catch (_) {}

      // Ad-hoc quick-connect sessions have no stored identity; reconnecting
      // with a server identity would silently switch credentials.
      final identityId = session.usedDirectIdentity
          ? null
          : (session.identityId ??
              (session.server.identities?.isNotEmpty == true
                  ? session.server.identities!.first
                  : null));

      final queryParams = <String, String>{
        'sessionToken': token,
        'entryId': session.server.id.toString(),
        'sessionId': session.sessionId,
        if (identityId != null) 'identityId': identityId.toString(),
      };

      final channel = IOWebSocketChannel.connect(
        Uri.parse(ApiClient.buildWebSocketUrl('/ws/term', queryParams: queryParams)),
        headers: {'User-Agent': ApiClient.userAgent},
      );

      session.termChannel = channel;
      session.identityId = identityId;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> reconnectSftpSession({
    required String token,
    required AppSession session,
  }) async {
    try {
      session.sftpSubscription?.cancel();
      session.sftpSubscription = null;
      try { session.sftpChannel?.sink.close(); } catch (_) {}

      final queryParams = <String, String>{
        'sessionToken': token,
        'sessionId': session.sessionId,
      };

      final channel = IOWebSocketChannel.connect(
        Uri.parse(ApiClient.buildWebSocketUrl('/ws/sftp', queryParams: queryParams)),
        headers: {'User-Agent': ApiClient.userAgent},
      );

      session.sftpChannel = channel;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> reconnectGuacSession({
    required String token,
    required AppSession session,
  }) async {
    try {
      _disconnectSession(session);
      final tunnel = GuacWebSocketTunnel(ApiClient.buildWebSocketUrl('/ws/guac/'));
      final client = GuacClient(tunnel);

      session.guacTunnel = tunnel;
      session.guacClient = client;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> closeAll(String token) async {
    final ids = _sessions.keys.toList();
    for (final id in ids) {
      final session = _sessions[id];
      if (session == null) continue;
      _disconnectSession(session);
      try {
        await ConnectionService.deleteSession(token: token, sessionId: id);
      } catch (_) {}
      _sessions.remove(id);
    }
    _activeSessionId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final session in _sessions.values) {
      _disconnectSession(session);
    }
    _sessions.clear();
    super.dispose();
  }
}
