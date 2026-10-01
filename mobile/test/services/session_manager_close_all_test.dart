import 'package:flutter_test/flutter_test.dart';
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

  test('closeSession on missing id is a safe no-op', () async {
    final sm = SessionManager();
    await sm.closeSession('missing', 'test-token');
    expect(sm.sessions, isEmpty);
    expect(sm.activeSessionId, isNull);
  });
}
