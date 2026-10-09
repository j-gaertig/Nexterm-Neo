import '../api/nexterm_api.dart';
import '../auth/client_ids.dart';
import '../servers/identity.dart';
import '../servers/server_models.dart';

/// Which viewer to open for a session.
enum SessionKind { terminal, files, desktop }

/// An opened remote session ready for a viewer screen.
class RemoteSession {
  const RemoteSession({
    required this.sessionId,
    required this.entry,
    required this.kind,
    this.identityId,
  });

  final String sessionId;
  final ServerEntry entry;
  final SessionKind kind;
  final int? identityId;
}

/// Source of active connections for the servers page.
abstract class ConnectionListProvider {
  Future<List<ConnectionInfo>> activeSessions();
}

/// Opens a remote session: resolves an identity, then
/// `POST /api/connections/`. No viewer logic here.
class SessionOpener implements ConnectionListProvider {
  SessionOpener({required this.api, required this.token});

  final NextermApi api;
  final String token;

  /// First identity of the entry that still exists, if any.
  Future<int?> resolveIdentityId(ServerEntry entry) async {
    if (entry.identities.isEmpty) return null;
    try {
      final all = await api.fetchIdentities(token);
      final available = all
          .map((m) {
            final raw = m['id'];
            return raw is num ? raw.toInt() : int.tryParse('$raw');
          })
          .whereType<int>()
          .toSet();
      for (final id in entry.identities) {
        if (available.contains(id)) return id;
      }
      return entry.identities.first;
    } catch (_) {
      return entry.identities.first;
    }
  }

  Future<RemoteSession> open(ServerEntry entry, SessionKind kind,
      {int? identityId,
      String? startPath,
      int? scriptId,
      String? connectionType,
      String? connectionReason}) async {
    final resolved =
        identityId ?? await resolveIdentityId(entry);
    final body = <String, dynamic>{
      'entryId': entry.id,
      'tabId': ClientIds.appInstanceId(),
    };
    body['browserId'] = await ClientIds.deviceId();
    if (resolved != null) body['identityId'] = resolved;
    // Session type: explicit override wins, files default to sftp
    // ('web' opens the server-side proxied browser via guac).
    final ct = connectionType ?? (kind == SessionKind.files ? 'sftp' : null);
    if (ct != null) body['type'] = ct;
    final sp = startPath;
    if (sp != null && sp.isNotEmpty) body['startPath'] = sp;
    final sid = scriptId;
    if (sid != null) body['scriptId'] = sid;
    final reason = connectionReason;
    if (reason != null && reason.isNotEmpty) {
      body['connectionReason'] = reason;
    }
    final result = await api.createConnection(token, body);
    final sessionId = result['sessionId'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      throw NextermApiException('Invalid server response.');
    }
    return RemoteSession(
        sessionId: sessionId,
        entry: entry,
        kind: kind,
        identityId: resolved);
  }

  @override
  Future<List<ConnectionInfo>> activeSessions() async {
    // Unfiltered: badges + sheets show sessions from all devices/tabs
    // (web SessionContext parity), not just this app instance.
    final raw = await api.listConnections(token);
    return raw
        .map((m) {
          try {
            return ConnectionInfo.fromJson(m);
          } catch (_) {
            return null;
          }
        })
        .whereType<ConnectionInfo>()
        .where((c) => c.sessionId.isNotEmpty && c.entryId >= 0)
        .toList();
  }

  Future<void> close(String sessionId) =>
      api.deleteConnection(token, sessionId);

  Future<void> resume(String sessionId) => api.resumeConnection(
      token,
      sessionId,
      {
        'tabId': ClientIds.appInstanceId(),
      });
}
