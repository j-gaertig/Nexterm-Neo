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
  VoidCallback? onSessionExpired,
}) {
  final session = RemoteSession(
      sessionId: sessionId, entry: entry, kind: kind);
  final page = switch (kind) {
    SessionKind.terminal => TerminalScreen(
        api: api,
        sessionToken: token,
        session: session,
        onSessionExpired: onSessionExpired),
    SessionKind.files => FilesScreen(
        api: api,
        sessionToken: token,
        session: session,
        onSessionExpired: onSessionExpired),
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

/// Audit-reason prompt for organizations with `requireConnectionReason`.
/// Returns the reason, or null when dismissed.
Future<String?> _askConnectionReason(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Connection reason'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'This organization requires a reason for audit logging.'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Reason',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) =>
                Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final reason = controller.text.trim();
            Navigator.pop(ctx, reason.isEmpty ? null : reason);
          },
          child: const Text('Connect'),
        ),
      ],
    ),
  ).then((reason) {
    controller.dispose();
    return reason;
  });
}

/// Open an existing connection in its viewer (resumes hibernated ones).
Future<void> openConnectionViewer(
  BuildContext context, {
  required NextermApi api,
  required String token,
  required ServerEntry entry,
  required ConnectionInfo info,
  VoidCallback? onSessionExpired,
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
      kind: kindForConnection(info),
      onSessionExpired: onSessionExpired);
}

/// Create a new session with progress UI, then open its viewer.
Future<void> startNewSession(
  BuildContext context, {
  required NextermApi api,
  required String token,
  required ServerEntry entry,
  required SessionKind kind,
  int? scriptId,
  String? connectionType,
  VoidCallback? onSessionExpired,
  String? connectionReason,
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
    if (dialogOpen && context.mounted) {
      dialogOpen = false;
      Navigator.pop(context);
    }
  }

  late final RemoteSession session;
  try {
    session = await SessionOpener(api: api, token: token).open(
        entry, kind,
        scriptId: scriptId,
        connectionType: connectionType,
        connectionReason: connectionReason);
  } on NextermApiException catch (e) {
    // Organizations can require an audit reason
    // (`requireConnectionReason`): ask and retry once.
    if (e.message != 'Connection reason required' ||
        !context.mounted) {
      closeDialog();
      if (context.mounted) _fail(context, e);
      return;
    }
    closeDialog();
    final reason = await _askConnectionReason(context);
    if (reason == null || !context.mounted) return;
    await startNewSession(context,
        api: api,
        token: token,
        entry: entry,
        kind: kind,
        scriptId: scriptId,
        connectionType: connectionType,
        onSessionExpired: onSessionExpired,
        connectionReason: reason);
    return;
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
      kind: session.kind,
      onSessionExpired: onSessionExpired);
}
