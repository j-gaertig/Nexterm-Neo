import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexterm_v2/api/nexterm_api.dart';
import 'package:nexterm_v2/auth/session_store.dart';
import 'package:nexterm_v2/main.dart';
import 'package:nexterm_v2/screens/home_shell.dart';
import 'package:nexterm_v2/widgets/wobbly_nav_bar.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('normalizeBaseUrl appends /api and adds https', () {
    expect(NextermApi.normalizeBaseUrl('nexterm.example.com'),
        'https://nexterm.example.com/api');
    expect(NextermApi.normalizeBaseUrl('http://host:6989/'),
        'http://host:6989/api');
    expect(NextermApi.normalizeBaseUrl('https://host/api'),
        'https://host/api');
    expect(NextermApi.normalizeBaseUrl('HTTPS://HOST/'),
        'HTTPS://HOST/api');
    expect(NextermApi.normalizeBaseUrl('https://host/API'),
        'https://host/API');
  });

  testWidgets('Login screen shows server URL field', (tester) async {
    await tester.pumpWidget(const NextermApp());
    await tester.pumpAndSettle();
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Scan QR code'), findsOneWidget);
  });

  testWidgets('HomeShell starts on Home (center)', (tester) async {
    const session = SessionInfo(
        token: 't', baseUrl: 'https://host/api', label: 'host');
    await tester.pumpWidget(
      const MaterialApp(home: HomeShell(session: session, onLogout: _noop)),
    );
    await tester.pumpAndSettle();
    // Navbar shows all 5 entries, Home page is visible.
    for (final label
        in ['Servers', 'Monitoring', 'Home', 'More', 'Settings']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Connected to host.'), findsOneWidget);
  });

  testWidgets('Tapping Servers switches the page', (tester) async {
    const session = SessionInfo(
        token: 't', baseUrl: 'https://host/api', label: 'host');
    await tester.pumpWidget(
      const MaterialApp(home: HomeShell(session: session, onLogout: _noop)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(WobblyNavBar),
      matching: find.text('Servers'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Webserver'), findsOneWidget);
    expect(find.text('Windows Box'), findsOneWidget);
  });

  testWidgets('Tapping a server opens the sessions sheet', (tester) async {
    const session = SessionInfo(
        token: 't', baseUrl: 'https://host/api', label: 'host');
    await tester.pumpWidget(
      const MaterialApp(home: HomeShell(session: session, onLogout: _noop)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(WobblyNavBar),
      matching: find.text('Servers'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Webserver'));
    await tester.pumpAndSettle();
    expect(find.text('Active sessions (3)'), findsOneWidget);
    expect(find.text('New session'), findsOneWidget);
    expect(find.text('SFTP'), findsWidgets);
    expect(find.text('Close all'), findsOneWidget);
  });

  testWidgets('Long-pressing a server opens the actions sheet',
      (tester) async {
    const session = SessionInfo(
        token: 't', baseUrl: 'https://host/api', label: 'host');
    await tester.pumpWidget(
      const MaterialApp(home: HomeShell(session: session, onLogout: _noop)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(WobblyNavBar),
      matching: find.text('Servers'),
    ));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Webserver'));
    await tester.pumpAndSettle();
    expect(find.text('Quick connect'), findsOneWidget);
    expect(find.text('Wake on LAN'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  test('Apple glass only on iOS/macOS', () {
    expect(wobblyNavUsesAppleGlass(TargetPlatform.iOS), isTrue);
    expect(wobblyNavUsesAppleGlass(TargetPlatform.macOS), isTrue);
    expect(wobblyNavUsesAppleGlass(TargetPlatform.android), isFalse);
  });

  testWidgets('Monitoring list shows monitored servers', (tester) async {
    const session = SessionInfo(
        token: 't', baseUrl: 'https://host/api', label: 'host');
    await tester.pumpWidget(
      const MaterialApp(home: HomeShell(session: session, onLogout: _noop)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(WobblyNavBar),
      matching: find.text('Monitoring'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Webserver'), findsOneWidget);
    expect(find.text('NAS'), findsOneWidget);
    expect(find.text('Windows Box'), findsOneWidget);
    expect(find.text('Search servers'), findsOneWidget);
  });

  testWidgets('Monitoring search filters servers', (tester) async {
    const session = SessionInfo(
        token: 't', baseUrl: 'https://host/api', label: 'host');
    await tester.pumpWidget(
      const MaterialApp(home: HomeShell(session: session, onLogout: _noop)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(WobblyNavBar),
      matching: find.text('Monitoring'),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nas');
    await tester.pumpAndSettle();
    expect(find.text('NAS'), findsOneWidget);
    expect(find.text('Webserver'), findsNothing);
  });

  testWidgets('Tapping a monitored server opens the detail view',
      (tester) async {
    const session = SessionInfo(
        token: 't', baseUrl: 'https://host/api', label: 'host');
    await tester.pumpWidget(
      const MaterialApp(home: HomeShell(session: session, onLogout: _noop)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(WobblyNavBar),
      matching: find.text('Monitoring'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Webserver'));
    await tester.pumpAndSettle();
    // Overview tab with system + performance sections.
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Performance'), findsOneWidget);
    // Switch to Charts tab with time ranges.
    await tester.tap(find.text('Charts'));
    await tester.pumpAndSettle();
    expect(find.text('CPU usage'), findsOneWidget);
    expect(find.text('Memory usage'), findsOneWidget);
    expect(find.text('24h'), findsOneWidget);
    await tester.tap(find.text('24h'));
    await tester.pumpAndSettle();
    expect(find.text('CPU usage'), findsOneWidget);
  });
}

void _noop() {}
