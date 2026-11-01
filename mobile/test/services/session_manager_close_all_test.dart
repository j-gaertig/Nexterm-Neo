import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/server.dart';
import 'package:nexterm/services/session_manager.dart';

void main() {
  test('closeAll on empty clears active id with single notify', () async {
    final sm = SessionManager();
    var notified = 0;
    sm.addListener(() => notified++);
    await sm.closeAll('test-token');
    expect(sm.sessions, isEmpty);
    expect(sm.activeSessionId, isNull);
    expect(sm.hasActiveSessions, isFalse);
    expect(notified, 1);
  });

  test('discardAll drops local sessions without server calls', () {
    final sm = SessionManager();
    sm.seedSessionForTesting(AppSession(
      sessionId: 'home-session',
      server: const Server(name: 'home-assistant', ip: '192.168.1.60'),
      type: ConnectionType.terminal,
    ));
    var notified = 0;
    sm.addListener(() => notified++);
    sm.discardAll();
    expect(sm.sessions, isEmpty);
    expect(sm.activeSessionId, isNull);
    expect(sm.hasActiveSessions, isFalse);
    expect(notified, 1);
  });

  test('closeSession on missing id is a safe no-op', () async {
    final sm = SessionManager();
    await sm.closeSession('missing', 'test-token');
    expect(sm.sessions, isEmpty);
    expect(sm.activeSessionId, isNull);
  });
}
