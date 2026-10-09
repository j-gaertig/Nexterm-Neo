import 'package:flutter/material.dart';

import '../api/nexterm_api.dart';
import '../remote/session_opener.dart';
import '../screens/remote/desktop_screen.dart';
import '../screens/remote/files_screen.dart';
import '../screens/remote/terminal_screen.dart';
import '../servers/identity.dart';
import '../servers/server_models.dart';

/// Map a connection to the viewer kind (mirrors the web renderers).
///
/// Server `configuration.type` is only `sftp`/`web`/null and `renderer`
/// is the entry renderer (`guac` for RDP/VNC, `terminal` otherwise) —
/// see `server/controllers/serverSession.js`.
SessionKind kindForConnection(ConnectionInfo info) {
  final kind = (info.kind ?? '').toLowerCase();
  if (kind == 'sftp') return SessionKind.files;
  final renderer = (info.renderer ?? '').toLowerCase();
  if (renderer.contains('guac')) return SessionKind.desktop;
  return SessionKind.terminal;
}

void _pushViewer(
  BuildContext context, {
  required NextermApi api,
  required String token,
  required ServerEntry entry,
  required String sessionId,
  required SessionKind kind,
}) {
  final session = RemoteSession(
      sessionId: sessionId, entry: entry, kind: kind);
  final page = switch (kind) {
    SessionKind.terminal => TerminalScreen(
        api: api, sessionToken: token, session: session),
    SessionKind.files => FilesScreen(
        api: api, sessionToken: token, session: session),
    SessionKind.desktop => DesktopScreen(
        api: api, sessionToken: token, session: session),
  };
  Navigator.push(
      context, MaterialPageRoute(builder: (_) => page));
}

void _fail(BuildContext context, Object e) {
  final message = e is NextermApiException
      ? e.message
      : 'Could not open session.';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

/// Open an existing connection in its viewer (resumes hibernated ones).
Future<void> openConnectionViewer(
  BuildContext context, {
  required NextermApi api,
  required String token,
  required ServerEntry entry,
  required ConnectionInfo info,
}) async {
  if (info.hibernated) {
    try {
      await SessionOpener(api: api, token: token)
          .resume(info.sessionId);
    } catch (e) {
      if (context.mounted) _fail(context, e);
      return;
    }
  }
  if (!context.mounted) return;
  _pushViewer(context,
      api: api,
      token: token,
      entry: entry,
      sessionId: info.sessionId,
      kind: kindForConnection(info));
}

/// Create a new session with progress UI, then open its viewer.
Future<void> startNewSession(
  BuildContext context, {
  required NextermApi api,
  required String token,
  required ServerEntry entry,
  required SessionKind kind,
}) async {
  // The dialog can be dismissed via Android back despite
  // barrierDismissible:false — track it so we never pop the page below.
  var dialogOpen = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        const Center(child: CircularProgressIndicator()),
  ).then((_) => dialogOpen = false);
  void closeDialog() {
    if (dialogOpen) {
      dialogOpen = false;
      Navigator.pop(context);
    }
  }

  late final RemoteSession session;
  try {
    session = await SessionOpener(api: api, token: token)
        .open(entry, kind);
  } catch (e) {
    if (!context.mounted) return;
    closeDialog();
    _fail(context, e);
    return;
  }
  if (!context.mounted) return;
  closeDialog();
  _pushViewer(context,
      api: api,
      token: token,
      entry: entry,
      sessionId: session.sessionId,
      kind: session.kind);
}
