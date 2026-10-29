import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexterm/models/server.dart';
import 'package:nexterm/screens/renderers/password_fill_hint.dart';
import 'package:nexterm/screens/renderers/terminal_renderer.dart';
import 'package:nexterm/services/session_manager.dart';
import 'package:nexterm/utils/ai_manager.dart';
import 'package:nexterm/utils/app_icons.dart';
import 'package:nexterm/utils/snippet_manager.dart';
import 'package:nexterm/utils/terminal_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kterm/kterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('uses a line cursor and advances through echoed terminal text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await TerminalSettings.load();
    final terminal = Terminal(maxLines: 100);
    final session = AppSession(
      sessionId: 'test-session',
      server: const Server(name: 'Test server', ip: '127.0.0.1'),
      type: ConnectionType.terminal,
      terminal: terminal,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: TerminalRenderer(
            session: session,
            token: 'test-token',
            sessionManager: SessionManager(),
            snippetManager: SnippetManager(),
            terminalSettings: settings,
            aiManager: AIManager(),
          ),
        ),
      ),
    );

    final terminalView = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(terminalView.cursorType, TerminalCursorType.block);
    expect(terminalView.theme.cursor, Colors.transparent);
    expect(terminalView.keyboardType, TextInputType.visiblePassword);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString().contains('LineCursorPainter'),
      ),
      findsOneWidget,
    );

    final initialCursorTop = tester
        .state<TerminalViewState>(find.byType(TerminalView))
        .globalCursorRect
        .top;

    terminal.write('first');
    expect(terminal.buffer.cursorX, 5);
    terminal.write(' ');
    expect(terminal.buffer.cursorX, 6);
    terminal.write('word!');
    expect(terminal.buffer.cursorX, 11);
    terminal.write('\r\n');
    expect(terminal.buffer.cursorX, 0);
    expect(terminal.buffer.cursorY, 1);

    await tester.pump();
    final cursorRect = tester
        .state<TerminalViewState>(find.byType(TerminalView))
        .globalCursorRect;
    expect(cursorRect.top, greaterThan(initialCursorTop));

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
  });

  testWidgets(
    'shows uniform arrow icons in the keyboard toolbar when focused',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await TerminalSettings.load();
      final terminal = Terminal(maxLines: 100);
      final session = AppSession(
        sessionId: 'test-session',
        server: const Server(name: 'Test server', ip: '127.0.0.1'),
        type: ConnectionType.terminal,
        terminal: terminal,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 600,
            child: TerminalRenderer(
              session: session,
              token: 'test-token',
              sessionManager: SessionManager(),
              snippetManager: SnippetManager(),
              terminalSettings: settings,
              aiManager: AIManager(),
            ),
          ),
        ),
      );

      // The connection loader covers the terminal until the first WebSocket
      // frame arrives. Focus the terminal directly; this test is about the
      // keyboard toolbar, not connection state.
      final terminalView = tester.widget<TerminalView>(
        find.byType(TerminalView),
      );
      terminalView.focusNode!.requestFocus();
      await tester.pump();

      expect(find.byIcon(AppIcons.arrowUp), findsOneWidget);
      expect(find.byIcon(AppIcons.arrowDown), findsOneWidget);
      expect(find.byIcon(AppIcons.arrowLeft), findsOneWidget);
      expect(find.byIcon(AppIcons.arrowRight), findsOneWidget);
      expect(tester.widget<Icon>(find.byIcon(AppIcons.arrowUp)).size, 18);
      expect(tester.widget<Icon>(find.byIcon(AppIcons.arrowDown)).size, 18);
      expect(tester.widget<Icon>(find.byIcon(AppIcons.arrowLeft)).size, 18);
      expect(tester.widget<Icon>(find.byIcon(AppIcons.arrowRight)).size, 18);
      expect(find.text('↑'), findsNothing);
      expect(find.text('↓'), findsNothing);
      expect(find.text('←'), findsNothing);
      expect(find.text('→'), findsNothing);

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(const SizedBox.shrink());
      settings.dispose();
    },
  );

  testWidgets(
    'shows the key button above the toolbar only while password detection is on',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await TerminalSettings.load();
      final terminal = Terminal(maxLines: 100);
      final session = AppSession(
        sessionId: 'test-session-password',
        server: const Server(
          name: 'Test server',
          ip: '127.0.0.1',
          identities: [1, 2],
        ),
        type: ConnectionType.terminal,
        terminal: terminal,
        identityId: 2,
      );

      // Delay the identity response so the detected prompt is already in the
      // terminal buffer when the prompt-race healing runs.
      final releaseIdentities = Completer<void>();
      final releaseFill = Completer<void>();
      var fillRequests = 0;
      Map<String, dynamic>? lastFillBody;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/identities/list')) {
          await releaseIdentities.future;
          return http.Response(
            jsonEncode([
              {
                'id': 1,
                'name': 'Deploy',
                'username': 'deploy',
                'type': 'password',
              },
              {'id': 2, 'name': 'Root', 'username': 'root', 'type': 'password'},
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('/paste-password')) {
          fillRequests++;
          lastFillBody = jsonDecode(request.body) as Map<String, dynamic>;
          await releaseFill.future;
          return http.Response('{}', 200);
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 800,
              height: 600,
              child: TerminalRenderer(
                session: session,
                token: 'test-token',
                sessionManager: SessionManager(),
                snippetManager: SnippetManager(),
                terminalSettings: settings,
                aiManager: AIManager(),
              ),
            ),
          ),
        );

        final terminalView = tester.widget<TerminalView>(
          find.byType(TerminalView),
        );
        terminalView.focusNode!.requestFocus();
        terminal.write('Password:');
        releaseIdentities.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(PasswordFillHint), findsOneWidget);
        expect(find.byIcon(AppIcons.key), findsOneWidget);
        expect(find.text('Password'), findsNothing);

        final hintRect = tester.getRect(find.byType(PasswordFillHint));
        final terminalRect = tester.getRect(find.byType(TerminalView));
        expect(hintRect.right, moreOrLessEquals(terminalRect.right - 12));
        expect(hintRect.bottom, moreOrLessEquals(terminalRect.bottom - 12));

        // The toolbar is visible and the key button sits directly above it.
        expect(find.text('ESC'), findsOneWidget);
        final toolbarRect = tester.getRect(
          find
              .ancestor(of: find.text('ESC'), matching: find.byType(SafeArea))
              .first,
        );
        expect(hintRect.bottom, moreOrLessEquals(toolbarRect.top - 12));

        await settings.setPasswordPromptDetection(false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(PasswordFillHint), findsNothing);

        await settings.setPasswordPromptDetection(true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(PasswordFillHint), findsOneWidget);

        // Two rapid invocations (a double tap before the first request
        // completes) must only send one fill request, with submit enabled.
        final fillButton = tester.widget<InkWell>(
          find.descendant(
            of: find.byType(PasswordFillHint),
            matching: find.byType(InkWell),
          ),
        );
        fillButton.onTap!();
        fillButton.onTap!();
        await tester.pump();
        expect(fillRequests, 1);
        expect(lastFillBody?['submit'], isTrue);
        releaseFill.complete();
        await tester.pump();
      }, () => client);

      await tester.pumpWidget(const SizedBox.shrink());
      settings.dispose();
    },
  );
}
