import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/server.dart';
import 'package:nexterm/screens/sessions_overview_screen.dart';
import 'package:nexterm/screens/widgets/session_grid_card.dart';
import 'package:nexterm/services/session_manager.dart';

void main() {
  testWidgets('lays out sessions in two columns with name and protocol', (
    tester,
  ) async {
    await _pumpOverview(
      tester,
      sessions: [
        _session('one', 'edge-gateway', 'ssh', ConnectionType.terminal),
        _session('two', 'metrics-db', 'ssh', ConnectionType.terminal),
        _session('three', 'vault', 'sftp', ConnectionType.sftp),
      ],
    );

    final cards = find.byType(SessionGridCard);
    expect(cards, findsNWidgets(3));
    expect(find.text('3 active sessions'), findsOneWidget);

    final first = tester.getTopLeft(cards.at(0));
    final second = tester.getTopLeft(cards.at(1));
    final third = tester.getTopLeft(cards.at(2));

    expect(second.dy, first.dy);
    expect(third.dy, greaterThan(first.dy));
    expect(third.dx, first.dx);
    expect(second.dx, greaterThan(first.dx));

    expect(find.text('edge-gateway'), findsOneWidget);
    expect(find.text('SSH'), findsNWidgets(2));
    expect(find.text('SFTP'), findsOneWidget);
  });

  testWidgets('tapping a card opens it and the corner X closes it', (
    tester,
  ) async {
    final opened = <String>[];
    final closed = <String>[];
    await _pumpOverview(
      tester,
      sessions: [
        _session('one', 'edge-gateway', 'ssh', ConnectionType.terminal),
        _session('two', 'vault', 'sftp', ConnectionType.sftp),
      ],
      onOpenSession: opened.add,
      onCloseSession: closed.add,
    );

    await tester.tap(find.text('edge-gateway'));
    expect(opened, ['one']);

    final secondCard = find.byType(SessionGridCard).at(1);
    await tester.tap(
      find.descendant(
        of: secondCard,
        matching: find.byTooltip('Close session'),
      ),
    );
    expect(closed, ['two']);
    expect(opened, ['one']);
  });

  testWidgets('shows an empty state without a back-to-servers action', (
    tester,
  ) async {
    await _pumpOverview(tester, sessions: const []);

    expect(find.text('No active sessions'), findsOneWidget);
    expect(find.text('Close all'), findsNothing);
    expect(find.text('Back to servers'), findsNothing);
  });
}

AppSession _session(
  String id,
  String name,
  String protocol,
  ConnectionType type,
) {
  return AppSession(
    sessionId: id,
    server: Server(name: name, ip: '10.0.0.1', protocol: protocol),
    type: type,
  );
}

Future<void> _pumpOverview(
  WidgetTester tester, {
  required List<AppSession> sessions,
  ValueChanged<String>? onOpenSession,
  ValueChanged<String>? onCloseSession,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final manager = SessionManager();
  for (final session in sessions) {
    manager.seedSessionForTesting(session);
  }
  addTearDown(manager.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: SessionsOverviewScreen(
        sessionManager: manager,
        previews: const {},
        onOpenSession: onOpenSession ?? (_) {},
        onCloseSession: onCloseSession ?? (_) {},
      ),
    ),
  );
  await tester.pump();
}
