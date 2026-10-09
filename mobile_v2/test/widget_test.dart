import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexterm_v2/api/nexterm_api.dart';
import 'package:nexterm_v2/auth/session_store.dart';
import 'package:nexterm_v2/main.dart';
import 'package:nexterm_v2/screens/home_shell.dart';
import 'package:nexterm_v2/screens/pages/server_detail_sheet.dart';
import 'package:nexterm_v2/screens/pages/servers_page.dart';
import 'package:nexterm_v2/servers/server_models.dart';
import 'package:nexterm_v2/servers/server_repository.dart';
import 'package:nexterm_v2/widgets/wobbly_nav_bar.dart';

class _FakeServers implements ServerRepository {
  const _FakeServers({this.servers = const [], this.error});

  final List<ServerEntry> servers;
  final Exception? error;

  @override
  Future<List<ServerEntry>> fetchServers() async {
    final e = error;
    if (e != null) throw e;
    return servers;
  }
}

const _fakeServers = [
  ServerEntry(id: 1, name: 'Webserver', ip: '192.168.1.10', protocol: 'ssh'),
  ServerEntry(id: 2, name: 'Windows Box', ip: '192.168.1.20', protocol: 'rdp'),
];

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
      const MaterialApp(
          home: HomeShell(
              session: session,
              onLogout: _noop,
              serversRepository:
                  _FakeServers(servers: _fakeServers))),
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
      const MaterialApp(
          home: HomeShell(
              session: session,
              onLogout: _noop,
              serversRepository:
                  _FakeServers(servers: _fakeServers))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(WobblyNavBar),
      matching: find.text('Servers'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Webserver'), findsOneWidget);
    expect(find.text('192.168.1.10 • SSH'), findsOneWidget);
    expect(find.text('Connected to host.'), findsNothing);
  });

  testWidgets('Servers page lists real entries', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServersPage(
            repository: _FakeServers(servers: _fakeServers),
            onSessionExpired: _noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Webserver'), findsOneWidget);
    expect(find.text('192.168.1.10 • SSH'), findsOneWidget);
    expect(find.text('Windows Box'), findsOneWidget);
  });

  testWidgets('Servers page shows empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServersPage(
            repository: _FakeServers(),
            onSessionExpired: _noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No servers yet.'), findsOneWidget);
  });

  testWidgets('Servers page shows error with retry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServersPage(
            repository: _FakeServers(
                error: NextermApiException('Server unreachable.')),
            onSessionExpired: _noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Server unreachable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Tapping a server opens the sessions sheet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServersPage(
            repository: _FakeServers(servers: _fakeServers),
            onSessionExpired: _noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Webserver'));
    await tester.pumpAndSettle();
    expect(find.text('Active sessions (0)'), findsOneWidget);
    expect(find.text('No active sessions.'), findsOneWidget);
    expect(find.text('New session'), findsOneWidget);
    expect(find.text('SFTP'), findsOneWidget);
  });

  testWidgets('Sheet lists active sessions with close buttons',
      (tester) async {
    const entry = ServerEntry(
        id: 1, name: 'Webserver', ip: '192.168.1.10', protocol: 'ssh');
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServerDetailSheet.sessions(
            entry: entry,
            sessions: [
              ServerSessionInfo(
                  id: 's1', serverId: 1, kind: 'ssh', openedAt: now),
              ServerSessionInfo(
                  id: 's2', serverId: 1, kind: 'sftp', openedAt: now),
              ServerSessionInfo(
                  id: 's3', serverId: 1, kind: 'ssh', openedAt: now),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Active sessions (3)'), findsOneWidget);
    expect(find.text('Close all'), findsOneWidget);
  });

  testWidgets('Long-pressing a server opens the actions sheet',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServersPage(
            repository: _FakeServers(servers: _fakeServers),
            onSessionExpired: _noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Webserver'));
    await tester.pumpAndSettle();
    expect(find.text('Quick connect'), findsOneWidget);
    expect(find.text('Wake on LAN'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  test('ServerEntry parses list nodes', () {
    final entry = ServerEntry.fromJson({
      'id': 7,
      'name': 'DB',
      'ip': '10.0.0.7',
      'protocol': 'ssh',
      'icon': 'server',
      'status': 'online',
      'macAddress': 'AA:BB:CC:DD:EE:FF',
      'wakeOnLanEnabled': true,
      'identities': [3, 5],
    });
    expect(entry.id, 7);
    expect(entry.address, '10.0.0.7');
    expect(entry.primaryProtocol, 'ssh');
    expect(entry.wakeOnLanEnabled, isTrue);
    expect(entry.identities, [3, 5]);
  });

  testWidgets('Expired session returns to login callback', (tester) async {
    var expired = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServersPage(
            repository:
                const _FakeServers(error: SessionExpiredException()),
            onSessionExpired: () => expired = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(expired, isTrue);
  });

  test('flattenServerEntries skips corrupt nodes', () {
    final servers = flattenServerEntries([
      {'id': 13, 'type': 'server', 'name': 'C', 'ip': '10.0.0.3'},
      {'id': 'nope', 'type': 'server', 'name': 'Broken'},
      {'type': 'server', 'name': 'No id'},
      'just a string',
      42,
      null,
    ]);
    expect(servers.map((s) => s.name).toList(), ['C']);
  });

  test('ServerEntry reads nested config port', () {
    final entry = ServerEntry.fromJson({
      'id': 9,
      'name': 'Legacy',
      'config': {'ip': '10.0.0.9', 'port': 2222},
    });
    expect(entry.address, ':2222');
    expect(formatServerSubtitle(entry), ':2222 • SSH');
  });

  test('formatServerSubtitle handles missing address', () {
    const entry = ServerEntry(id: 1, name: 'X', ip: '');
    expect(formatServerSubtitle(entry), 'No address');
    const withIp =
        ServerEntry(id: 1, name: 'X', ip: '10.0.0.1', protocol: 'rdp');
    expect(formatServerSubtitle(withIp), '10.0.0.1 • RDP');
  });
  test('flattenServerEntries collects server leaves in order', () {
    final servers = flattenServerEntries([
      {
        'id': 1,
        'type': 'folder',
        'name': 'Prod',
        'entries': [
          {'id': 11, 'type': 'server', 'name': 'A', 'ip': '10.0.0.1'},
          {
            'id': 2,
            'type': 'folder',
            'name': 'Nested',
            'entries': [
              {'id': 12, 'type': 'server', 'name': 'B', 'ip': '10.0.0.2'},
            ],
          },
        ],
      },
      {'id': 13, 'type': 'server', 'name': 'C', 'ip': '10.0.0.3'},
      {'id': 21, 'type': 'pve-shell', 'name': 'PVE shell'},
    ]);
    expect(servers.map((s) => s.name).toList(), ['A', 'B', 'C']);
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
      const MaterialApp(
          home: HomeShell(
              session: session,
              onLogout: _noop,
              serversRepository:
                  _FakeServers(servers: _fakeServers))),
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
      const MaterialApp(
          home: HomeShell(
              session: session,
              onLogout: _noop,
              serversRepository:
                  _FakeServers(servers: _fakeServers))),
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
      const MaterialApp(
          home: HomeShell(
              session: session,
              onLogout: _noop,
              serversRepository:
                  _FakeServers(servers: _fakeServers))),
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
