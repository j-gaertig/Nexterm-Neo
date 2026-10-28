import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/server.dart';
import 'package:nexterm/screens/renderers/sftp_renderer.dart';
import 'package:nexterm/services/session_manager.dart';
import 'package:nexterm/utils/sftp_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('system back returns to the previous directory', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SftpSettings.load();
    final sessionManager = SessionManager();
    final session = AppSession(
      sessionId: 'sftp-session',
      server: const Server(name: 'Files', ip: '127.0.0.1'),
      type: ConnectionType.sftp,
    );
    session.sftpPath = '/a/b';
    session.sftpRootPath = '/';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SftpRenderer(
            session: session,
            token: 'test-token',
            sessionManager: sessionManager,
            sftpSettings: settings,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(session.handleBack, isNotNull);

    // Navigating through the breadcrumb records the previous directory in the
    // SFTP history.
    await tester.tap(find.text('a'));
    await tester.pump();
    expect(session.sftpPath, '/a');

    expect(session.handleBack!(), isTrue);
    await tester.pump();
    expect(session.sftpPath, '/');

    // At the root the renderer leaves the event to the shell, which switches
    // to the servers tab without closing the session.
    expect(session.handleBack!(), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(session.handleBack, isNull);

    settings.dispose();
    sessionManager.dispose();
  });
}
