import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/server.dart';
import 'package:nexterm/screens/renderers/sftp_renderer.dart';
import 'package:nexterm/services/session_manager.dart';
import 'package:nexterm/utils/sftp_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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

  testWidgets('system back restores the scroll position of the parent folder',
      (tester) async {
    SharedPreferences.setMockInitialValues({'sftp_sortFoldersFirst': false});
    final settings = await SftpSettings.load();
    final sessionManager = SessionManager();
    final channel = _FakeSftpChannel();
    final session = AppSession(
      sessionId: 'sftp-scroll-session',
      server: const Server(name: 'Files', ip: '127.0.0.1'),
      type: ConnectionType.sftp,
      sftpChannel: channel,
    );
    session.sftpPath = '/';
    session.sftpRootPath = '/';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
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

    channel.emit(0x0, {'rootPath': '/', 'path': '/'});
    await tester.pump();
    final rootFiles = [
      for (var i = 0; i < 60; i++)
        {'name': 'f${i.toString().padLeft(2, '0')}', 'type': 'folder'},
    ];
    channel.emit(0x1, {'path': '/', 'files': rootFiles});
    await tester.pump();
    await tester.pump();

    final listFinder = find.byType(ListView);
    await tester.scrollUntilVisible(
      find.text('f45'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    final offsetBefore = tester.widget<ListView>(listFinder).controller!.offset;
    expect(offsetBefore, greaterThan(0));

    await tester.tap(find.text('f45'));
    await tester.pump();
    expect(session.sftpPath, '/f45');

    channel.emit(0x1, {
      'path': '/f45',
      'files': [
        {'name': 'note.txt', 'type': 'file', 'size': 4},
      ],
    });
    await tester.pump();

    // The system back gesture walks the directory history back to the root.
    expect(session.handleBack!(), isTrue);
    await tester.pump();
    expect(session.sftpPath, '/');

    // The parent is still loading and therefore shows the shorter subfolder
    // listing for a moment. That must not pull the remembered offset toward
    // the top of the list.
    await tester.pump(const Duration(milliseconds: 100));

    channel.emit(0x1, {'path': '/', 'files': rootFiles});
    await tester.pump();
    await tester.pump();

    final offsetAfter = tester.widget<ListView>(listFinder).controller!.offset;
    expect(offsetAfter, moreOrLessEquals(offsetBefore, epsilon: 1));

    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
    sessionManager.dispose();
  });
}

class _FakeSftpChannel implements IOWebSocketChannel {
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  final _FakeWebSocketSink _sink = _FakeWebSocketSink();

  void emit(int operation, Map<String, dynamic> payload) {
    final jsonBytes = utf8.encode(jsonEncode(payload));
    final message = Uint8List(1 + jsonBytes.length);
    message[0] = operation;
    message.setRange(1, message.length, jsonBytes);
    _incoming.add(message);
  }

  @override
  Stream get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not supported');
}

class _FakeWebSocketSink implements WebSocketSink {
  @override
  void add(dynamic data) {}

  @override
  Future<void> addStream(Stream stream) async {
    await stream.drain<void>();
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not supported');
}
