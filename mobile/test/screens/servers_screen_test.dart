import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/server.dart';
import 'package:nexterm/models/server_account.dart';
import 'package:nexterm/screens/servers_screen.dart';
import 'package:nexterm/screens/widgets/server_grid_card.dart';
import 'package:nexterm/services/session_manager.dart';
import 'package:nexterm/utils/app_icons.dart';
import 'package:nexterm/utils/auth_manager.dart';
import 'package:nexterm/utils/server_account_manager.dart';
import 'package:nexterm/utils/server_view_settings.dart';
import 'package:nexterm/utils/snippet_manager.dart';
import 'package:nexterm/utils/theme_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('grid cards show name, address and a single tag', (tester) async {
    await _pumpGrid(
      tester,
      entries: [
        _server(
          id: 1,
          name: 'prod-web-01',
          ip: '10.20.0.11',
          tags: [_production, _web],
        ),
      ],
    );

    final card = find.byType(ServerGridCard);
    expect(card, findsOneWidget);
    expect(tester.widget<ServerGridCard>(card).dense, isFalse);
    expect(
      find.descendant(of: card, matching: find.text('prod-web-01')),
      findsOne,
    );
    expect(
      find.descendant(of: card, matching: find.text('10.20.0.11')),
      findsOne,
    );
    expect(
      find.descendant(of: card, matching: find.text('Production')),
      findsOne,
    );
    expect(find.descendant(of: card, matching: find.text('+1')), findsOne);
    expect(find.descendant(of: card, matching: find.text('Web')), findsNothing);

    // The tag bar still offers every tag as a filter.
    expect(find.text('Production'), findsNWidgets(2));
  });

  testWidgets('grid adapts the requested columns to the available width', (
    tester,
  ) async {
    await _pumpGrid(
      tester,
      columns: 4,
      entries: [
        for (var i = 1; i <= 4; i++)
          _server(id: i, name: 'server-$i', ip: '10.0.0.$i'),
      ],
    );

    final cards = find.byType(ServerGridCard);
    expect(cards, findsNWidgets(4));

    final first = tester.getTopLeft(cards.at(0));
    final second = tester.getTopLeft(cards.at(1));
    final third = tester.getTopLeft(cards.at(2));
    final fourth = tester.getTopLeft(cards.at(3));

    expect(second.dy, first.dy);
    expect(third.dy, first.dy);
    expect(second.dx, greaterThan(first.dx));
    expect(third.dx, greaterThan(second.dx));
    expect(fourth.dy, greaterThan(first.dy));
    expect(fourth.dx, first.dx);
  });

  testWidgets('selecting a tag filters the grid and can be cleared', (
    tester,
  ) async {
    await _pumpGrid(
      tester,
      entries: [
        _server(
          id: 1,
          name: 'prod-web-01',
          ip: '10.20.0.11',
          tags: [_production],
        ),
        _server(id: 2, name: 'db-primary', ip: '10.20.0.12', tags: [_database]),
      ],
    );

    expect(find.byType(ServerGridCard), findsNWidgets(2));

    // Tapping the tag on a card filters the grid, just like the tag bar.
    final card = find.byType(ServerGridCard).first;
    await tester.tap(
      find.descendant(of: card, matching: find.text('Production')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ServerGridCard), findsOneWidget);
    expect(find.text('prod-web-01'), findsOneWidget);
    expect(find.text('db-primary'), findsNothing);
    expect(find.byIcon(AppIcons.close), findsOneWidget);

    await tester.tap(find.byIcon(AppIcons.close));
    await tester.pumpAndSettle();

    expect(find.byType(ServerGridCard), findsNWidgets(2));
  });

  testWidgets('cards in a row share the tallest card height', (tester) async {
    await _pumpGrid(
      tester,
      entries: [
        _server(
          id: 1,
          name: 'very-long-production-server-name',
          ip: '10.20.0.11',
        ),
        _server(id: 2, name: 'db', ip: '10.20.0.12'),
      ],
    );

    final cards = find.byType(ServerGridCard);
    expect(cards, findsNWidgets(2));
    expect(
      tester.getSize(cards.at(0)).height,
      tester.getSize(cards.at(1)).height,
    );
  });
}

Future<void> _pumpGrid(
  WidgetTester tester, {
  required List<dynamic> entries,
  int columns = 2,
}) async {
  SharedPreferences.setMockInitialValues({
    'server_view_mode': ServerViewMode.grid.name,
    'server_view_columns': columns,
  });

  final accountManager = ServerAccountManager();
  await accountManager.load();
  await accountManager.addAccount(
    ServerAccount(
      id: 'test-account',
      label: 'Test',
      baseUrl: 'https://nexterm.example.com',
      token: 'test-token',
    ),
  );
  await accountManager.switchAccount('test-account');

  final authManager = AuthManager(accountManager);
  final snippetManager = SnippetManager();
  final sessionManager = SessionManager();
  final viewSettings = await ServerViewSettings.load();
  final themeManager = ThemeManager(ThemeMode.dark, useDynamicColor: false);

  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: themeManager.darkTheme(),
      home: ServersScreen(
        authManager: authManager,
        snippetManager: snippetManager,
        sessionManager: sessionManager,
        serverViewSettings: viewSettings,
        loadEntries: (_) async => entries,
      ),
    ),
  );
  await tester.pumpAndSettle();

  addTearDown(() {
    viewSettings.dispose();
    themeManager.dispose();
    authManager.dispose();
    snippetManager.dispose();
    sessionManager.dispose();
  });
}

Server _server({
  required int id,
  required String name,
  required String ip,
  String? type,
  String? protocol = 'ssh',
  String? status = 'online',
  List<Tag> tags = const [],
}) {
  return Server(
    id: id,
    name: name,
    ip: ip,
    type: type ?? 'server',
    protocol: type == null ? protocol : null,
    status: status,
    tags: tags,
  );
}

const _production = Tag(id: 1, name: 'Production', color: '#22C55E');
const _web = Tag(id: 2, name: 'Web', color: '#3B82F6');
const _database = Tag(id: 3, name: 'Database', color: '#A855F7');
