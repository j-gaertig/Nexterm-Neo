import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexterm_v2/account/account_models.dart';
import 'package:nexterm_v2/api/nexterm_api.dart';
import 'package:nexterm_v2/auth/session_store.dart';
import 'package:nexterm_v2/main.dart';
import 'package:nexterm_v2/monitoring/monitoring_models.dart';
import 'package:nexterm_v2/monitoring/monitoring_repository.dart';
import 'package:nexterm_v2/remote/session_opener.dart';
import 'package:nexterm_v2/remote/viewer.dart';
import 'package:nexterm_v2/screens/pages/more_page.dart';
import 'package:nexterm_v2/screens/home_shell.dart';
import 'package:nexterm_v2/screens/pages/settings_identities_page.dart';
import 'package:nexterm_v2/screens/pages/settings_monitoring_page.dart';
import 'package:nexterm_v2/settings/app_settings.dart';
import 'package:nexterm_v2/screens/pages/server_detail_sheet.dart';
import 'package:nexterm_v2/screens/pages/settings_apikeys_page.dart';
import 'package:nexterm_v2/servers/ssh_import.dart';
import 'package:nexterm_v2/screens/pages/server_editor_screen.dart';
import 'package:nexterm_v2/screens/pages/servers_page.dart';
import 'package:nexterm_v2/servers/identity.dart';
import 'package:nexterm_v2/servers/server_models.dart';
import 'package:nexterm_v2/snippets/snippet_models.dart';
import 'package:nexterm_v2/servers/server_repository.dart';
import 'package:nexterm_v2/widgets/wobbly_nav_bar.dart';

class _FakeConnections implements ConnectionListProvider {
  const _FakeConnections({this.sessions = const []});

  final List<ConnectionInfo> sessions;

  @override
  Future<List<ConnectionInfo>> activeSessions() async => sessions;
}

class _FakeMonitoring implements MonitoringRepository {
  const _FakeMonitoring({this.servers = const []});

  final List<MonitoredServer> servers;

  @override
  Future<List<MonitoredServer>> fetchServers() async => servers;

  @override
  Future<MonitoredDetail> fetchDetail(String serverId, String range) async {
    final server = servers.firstWhere((s) => s.id == serverId,
        orElse: () => servers.first);
    return MonitoredDetail(
      detail: ServerDetail(
        hostname: server.name,
        os: 'TestOS',
        version: '1.0',
        arch: 'x86_64',
        uptimeSeconds: 3600,
        cpu: server.cpu ?? 0,
        mem: server.mem ?? 0,
        memTotalGb: 8,
        load: const [0.5, 0.4, 0.3],
        processes: 42,
        disks: const [],
        network: const [],
        procs: const [],
      ),
      history: ServerHistory.empty,
    );
  }
}

class _FakeServers implements ServerRepository {
  const _FakeServers({this.nodes = const [], this.error});

  final List<EntryNode> nodes;
  final Exception? error;

  @override
  Future<List<EntryNode>> fetchNodes() async {
    final e = error;
    if (e != null) throw e;
    return nodes;
  }
}

List<EntryNode> _fakeTree() => const [
      FolderNode(id: '1', name: 'Prod', children: [
        ServerNode(ServerEntry(
            id: 1, name: 'Webserver', ip: '192.168.1.10', protocol: 'ssh')),
        ServerNode(ServerEntry(
            id: 2, name: 'Windows Box', ip: '192.168.1.20', protocol: 'rdp')),
      ]),
      ServerNode(ServerEntry(
          id: 3, name: 'NAS', ip: '192.168.1.30', protocol: 'ssh')),
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
      MaterialApp(
          home: HomeShell(
              session: session,
              onLogout: _noop,
              settings: AppSettings(),
              serversRepository:
                  _FakeServers(nodes: _fakeTree()),
              recentsLoader: () async => const [
                    ServerEntry(
                        id: 1, name: 'Webserver', ip: '192.168.1.10'),
                  ],
              moreLoader: () async => const MoreData(snippets: [
                    Snippet(id: 1, name: 'Hello', command: 'echo hi'),
                  ], scripts: []),
              settingsProfileLoader: () async => const UserInfo(
                  id: 1, username: 'admin', firstName: 'Ada'),
              settingsSessionsLoader: () async => const [],)),
    );
    await tester.pumpAndSettle();
    // Navbar shows all 5 entries, Home page is visible.
    for (final label
        in ['Servers', 'Monitoring', 'Home', 'More', 'Settings']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Connected to host'), findsOneWidget);
    expect(find.text('Recent servers'), findsOneWidget);
  });

  testWidgets('More page shows snippets and scripts', (tester) async {
    const session = SessionInfo(
        token: 't', baseUrl: 'https://host/api', label: 'host');
    await tester.pumpWidget(
      MaterialApp(
          home: HomeShell(
              session: session,
              onLogout: _noop,
              settings: AppSettings(),
              serversRepository:
                  _FakeServers(nodes: _fakeTree()),
              monitoringRepository:
                  _FakeMonitoring(servers: _fakeMonitored()),
              recentsLoader: () async => const [
                    ServerEntry(
                        id: 1, name: 'Webserver', ip: '192.168.1.10'),
                  ],
              moreLoader: () async => const MoreData(snippets: [
                    Snippet(id: 1, name: 'Hello', command: 'echo hi'),
                  ], scripts: []),
              settingsProfileLoader: () async => const UserInfo(
                  id: 1, username: 'admin', firstName: 'Ada'),
              settingsSessionsLoader: () async => const [])),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(WobblyNavBar),
      matching: find.text('More'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Snippets (1)'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Scripts (0)'), findsOneWidget);
  });

  testWidgets('Settings page shows profile and logout', (tester) async {
    // Tall viewport so the whole hub builds without scrolling.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    const session = SessionInfo(
        token: 't', baseUrl: 'https://host/api', label: 'host');
    await tester.pumpWidget(
      MaterialApp(
          home: HomeShell(
              session: session,
              onLogout: _noop,
              settings: AppSettings(),
              serversRepository:
                  _FakeServers(nodes: _fakeTree()),
              monitoringRepository:
                  _FakeMonitoring(servers: _fakeMonitored()),
              recentsLoader: () async => const [
                    ServerEntry(
                        id: 1, name: 'Webserver', ip: '192.168.1.10'),
                  ],
              moreLoader: () async => const MoreData(snippets: [
                    Snippet(id: 1, name: 'Hello', command: 'echo hi'),
                  ], scripts: []),
              settingsProfileLoader: () async => const UserInfo(
                  id: 1, username: 'admin', firstName: 'Ada'),
              settingsSessionsLoader: () async => const [])),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(WobblyNavBar),
      matching: find.text('Settings'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Log out'), findsWidgets);
    expect(find.text('Login sessions'), findsOneWidget);
  });

  testWidgets('Tapping Servers switches the page', (tester) async {
    const session = SessionInfo(
        token: 't', baseUrl: 'https://host/api', label: 'host');
    await tester.pumpWidget(
      MaterialApp(
          home: HomeShell(
              session: session,
              onLogout: _noop,
              settings: AppSettings(),
              serversRepository:
                  _FakeServers(nodes: _fakeTree()),
              recentsLoader: () async => const [
                    ServerEntry(
                        id: 1, name: 'Webserver', ip: '192.168.1.10'),
                  ],
              moreLoader: () async => const MoreData(snippets: [
                    Snippet(id: 1, name: 'Hello', command: 'echo hi'),
                  ], scripts: []),
              settingsProfileLoader: () async => const UserInfo(
                  id: 1, username: 'admin', firstName: 'Ada'),
              settingsSessionsLoader: () async => const [],)),
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
            repository: _FakeServers(nodes: _fakeTree()),
            api: NextermApi(baseUrl: 'https://host/api'),
            token: 't',
            connections: const _FakeConnections(),
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

  testWidgets('Servers page shows open-session badges', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServersPage(
            repository: _FakeServers(nodes: _fakeTree()),
            api: NextermApi(baseUrl: 'https://host/api'),
            token: 't',
            connections: const _FakeConnections(sessions: [
              ConnectionInfo(
                  sessionId: 's1', entryId: 1, kind: 'ssh'),
              ConnectionInfo(
                  sessionId: 's2', entryId: 1, kind: 'sftp'),
            ]),
            onSessionExpired: _noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 open'), findsOneWidget);
  });

  testWidgets('Servers page shows empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServersPage(
            repository: const _FakeServers(),
            api: NextermApi(baseUrl: 'https://host/api'),
            token: 't',
            connections: const _FakeConnections(),
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
                error: const NextermApiException('Server unreachable.')),
            api: NextermApi(baseUrl: 'https://host/api'),
            token: 't',
            connections: const _FakeConnections(),
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
            repository: _FakeServers(nodes: _fakeTree()),
            api: NextermApi(baseUrl: 'https://host/api'),
            token: 't',
            connections: const _FakeConnections(),
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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServerDetailSheet.sessions(
            entry: entry,
            sessions: const [
              ConnectionInfo(
                  sessionId: 's1', entryId: 1, kind: 'ssh'),
              ConnectionInfo(
                  sessionId: 's2', entryId: 1, kind: 'sftp'),
              ConnectionInfo(
                  sessionId: 's3',
                  entryId: 1,
                  kind: 'ssh',
                  hibernated: true),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Active sessions (3)'), findsOneWidget);
    expect(find.text('Close all'), findsOneWidget);
    expect(find.text('Hibernated — tap to resume'), findsOneWidget);
  });

  testWidgets('Servers page shows folders and collapses them',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServersPage(
            repository: _FakeServers(nodes: _fakeTree()),
            api: NextermApi(baseUrl: 'https://host/api'),
            token: 't',
            connections: const _FakeConnections(),
            onSessionExpired: _noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Prod (2)'), findsOneWidget);
    expect(find.text('NAS'), findsOneWidget);
    // Collapse the folder.
    await tester.tap(find.text('Prod (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Webserver'), findsNothing);
    expect(find.text('NAS'), findsOneWidget);
  });

  testWidgets('Servers page search filters flat', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServersPage(
            repository: _FakeServers(nodes: _fakeTree()),
            api: NextermApi(baseUrl: 'https://host/api'),
            token: 't',
            connections: const _FakeConnections(),
            onSessionExpired: _noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nas');
    await tester.pumpAndSettle();
    expect(find.text('NAS'), findsOneWidget);
    expect(find.text('Webserver'), findsNothing);
    expect(find.text('Prod (2)'), findsNothing);
  });

  testWidgets('Servers page toggles grid view', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServersPage(
            repository: _FakeServers(nodes: _fakeTree()),
            api: NextermApi(baseUrl: 'https://host/api'),
            token: 't',
            connections: const _FakeConnections(),
            onSessionExpired: _noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    await tester.tap(find.byTooltip('Grid view'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsWidgets);
    expect(find.byTooltip('List view'), findsOneWidget);
  });

  testWidgets('Overflow menu opens the actions sheet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServersPage(
            repository: _FakeServers(nodes: _fakeTree()),
            api: NextermApi(baseUrl: 'https://host/api'),
            token: 't',
            connections: const _FakeConnections(),
            onSessionExpired: _noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Server actions').first);
    await tester.pumpAndSettle();
    expect(find.text('Quick connect'), findsOneWidget);
  });
  testWidgets('Long-pressing a server opens the actions sheet',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServersPage(
            repository: _FakeServers(nodes: _fakeTree()),
            api: NextermApi(baseUrl: 'https://host/api'),
            token: 't',
            connections: const _FakeConnections(),
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

  test('buildEntryPayload merges base config on edit', () {
    final payload = buildEntryPayload(
      name: 'DB',
      protocol: 'ssh',
      ip: '10.0.0.7',
      baseConfig: {
        'protocol': 'ssh',
        'ip': '10.0.0.7',
        'port': 22,
        'macAddress': 'AA:BB:CC:DD:EE:FF',
        'wakeOnLanEnabled': true,
        'monitoringEnabled': true,
      },
    );
    final config = payload['config'] as Map;
    expect(config['macAddress'], 'AA:BB:CC:DD:EE:FF');
    expect(config['wakeOnLanEnabled'], isTrue);
    expect(config['monitoringEnabled'], isTrue);
    expect(config.containsKey('port'), isFalse);
  });

  test('kindForConnection maps renderer and type', () {
    const guac = ConnectionInfo(
        sessionId: 's', entryId: 1, renderer: 'guac');
    expect(kindForConnection(guac), SessionKind.desktop);
    const sftp = ConnectionInfo(
        sessionId: 's', entryId: 1, kind: 'sftp');
    expect(kindForConnection(sftp), SessionKind.files);
    const term = ConnectionInfo(
        sessionId: 's', entryId: 1, renderer: 'terminal');
    expect(kindForConnection(term), SessionKind.terminal);
  });

  test('MonitoredServer parses merged monitoring item', () {
    final server = MonitoredServer.fromJson({
      'id': 5,
      'name': 'Web',
      'ip': '10.0.0.5',
      'port': 22,
      'type': 'server',
      'status': 'online',
      'monitoring': {
        'cpuUsage': 12.5,
        'memoryUsage': '44.1',
        'loadAverage': [0.5, 0.4],
        'processes': 90,
        'uptime': 7200,
        'timestamp': '2026-10-09T10:00:00.000Z',
      },
    });
    expect(server.id, '5');
    expect(server.cpu, 12.5);
    expect(server.mem, 44.1);
    expect(server.load, 0.5);
    expect(server.lastSeen, isNotNull);
  });

  test('parseHistory sorts oldest first and skips bad rows', () {
    final history = parseHistory([
      {'timestamp': '2026-10-09T10:02:00.000Z', 'cpuUsage': 20},
      {'timestamp': 'not-a-date', 'cpuUsage': 99},
      {'timestamp': '2026-10-09T10:00:00.000Z', 'cpuUsage': 10},
      {'nope': true},
    ]);
    expect(history.cpu.map((p) => p.value).toList(), [10.0, 20.0]);
    expect(history.mem, isEmpty);
  });
  test('buildEntryPayload shapes create/update bodies', () {
    expect(
      buildEntryPayload(
          name: 'DB',
          protocol: 'ssh',
          ip: '10.0.0.7',
          port: 2222,
          identities: [3]),
      {
        'name': 'DB',
        'type': 'server',
        'config': {'protocol': 'ssh', 'ip': '10.0.0.7', 'port': 2222},
        'identities': [3],
      },
    );
    final noPort =
        buildEntryPayload(name: 'X', protocol: 'rdp', ip: 'h');
    expect((noPort['config'] as Map).containsKey('port'), isFalse);
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
            api: NextermApi(baseUrl: 'https://host/api'),
            token: 't',
            connections: const _FakeConnections(),
            onSessionExpired: () => expired = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(expired, isTrue);
  });

  test('parseEntryTree keeps folders and skips corrupt nodes', () {
    final nodes = parseEntryTree([
      {'id': 13, 'type': 'server', 'name': 'C', 'ip': '10.0.0.3'},
      {'id': 'nope', 'type': 'server', 'name': 'Broken'},
      {'type': 'server', 'name': 'No id'},
      'just a string',
      42,
      null,
    ]);
    expect(nodes.length, 1);
    expect((nodes.first as ServerNode).entry.name, 'C');
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
  test('parseEntryTree preserves folders and prunes empties', () {
    final nodes = parseEntryTree([
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
      {
        'id': 3,
        'type': 'folder',
        'name': 'Empty',
        'entries': [
          {'id': 21, 'type': 'pve-shell', 'name': 'PVE shell'},
        ],
      },
      {'id': 'org-9', 'type': 'organization', 'name': 'Team'},
      {'id': 13, 'type': 'server', 'name': 'C', 'ip': '10.0.0.3'},
    ]);
    // Prod + Empty folders + top-level server; the organization shell
    // without servers is pruned. Empty real folders are kept so newly
    // created ones stay visible.
    expect(nodes.length, 3);
    final folder = nodes.first as FolderNode;
    expect(folder.name, 'Prod');
    expect((nodes[1] as FolderNode).name, 'Empty');
    expect(flattenNodes(nodes).map((s) => s.name).toList(),
        ['A', 'B', 'C']);
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
      MaterialApp(
          home: HomeShell(
              session: session,
              onLogout: _noop,
              settings: AppSettings(),
              serversRepository:
                  _FakeServers(nodes: _fakeTree()),
              monitoringRepository:
                  _FakeMonitoring(servers: _fakeMonitored()),
              recentsLoader: () async => const [
                    ServerEntry(
                        id: 1, name: 'Webserver', ip: '192.168.1.10'),
                  ],
              moreLoader: () async => const MoreData(snippets: [
                    Snippet(id: 1, name: 'Hello', command: 'echo hi'),
                  ], scripts: []),
              settingsProfileLoader: () async => const UserInfo(
                  id: 1, username: 'admin', firstName: 'Ada'),
              settingsSessionsLoader: () async => const [],)),
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
      MaterialApp(
          home: HomeShell(
              session: session,
              onLogout: _noop,
              settings: AppSettings(),
              serversRepository:
                  _FakeServers(nodes: _fakeTree()),
              monitoringRepository:
                  _FakeMonitoring(servers: _fakeMonitored()),
              recentsLoader: () async => const [
                    ServerEntry(
                        id: 1, name: 'Webserver', ip: '192.168.1.10'),
                  ],
              moreLoader: () async => const MoreData(snippets: [
                    Snippet(id: 1, name: 'Hello', command: 'echo hi'),
                  ], scripts: []),
              settingsProfileLoader: () async => const UserInfo(
                  id: 1, username: 'admin', firstName: 'Ada'),
              settingsSessionsLoader: () async => const [],)),
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
      MaterialApp(
          home: HomeShell(
              session: session,
              onLogout: _noop,
              settings: AppSettings(),
              serversRepository:
                  _FakeServers(nodes: _fakeTree()),
              monitoringRepository:
                  _FakeMonitoring(servers: _fakeMonitored()),
              recentsLoader: () async => const [
                    ServerEntry(
                        id: 1, name: 'Webserver', ip: '192.168.1.10'),
                  ],
              moreLoader: () async => const MoreData(snippets: [
                    Snippet(id: 1, name: 'Hello', command: 'echo hi'),
                  ], scripts: []),
              settingsProfileLoader: () async => const UserInfo(
                  id: 1, username: 'admin', firstName: 'Ada'),
              settingsSessionsLoader: () async => const [],)),
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

  testWidgets('Settings hub shows account, server and app groups',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    const session = SessionInfo(
        token: 't', baseUrl: 'https://host/api', label: 'host');
    await tester.pumpWidget(
      MaterialApp(
          home: HomeShell(
              session: session,
              onLogout: _noop,
              settings: AppSettings(),
              serversRepository:
                  _FakeServers(nodes: _fakeTree()),
              recentsLoader: () async => const [],
              moreLoader: () async =>
                  const MoreData(snippets: [], scripts: []),
              settingsProfileLoader: () async => const UserInfo(
                  id: 1, username: 'admin', firstName: 'Ada'),
              settingsSessionsLoader: () async => const [])),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(WobblyNavBar),
      matching: find.text('Settings'),
    ));
    await tester.pumpAndSettle();
    for (final label in [
      'Account',
      'Server',
      'Appearance',
      'Terminal & files',
      'Lists & monitoring',
      'Identities',
      'Edit name',
      'Change password',
      'Profile picture',
      'Two-factor',
      'API keys',
      'Link device',
      'Audit log',
      'Grid by default',
    ]) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('Identities page shows empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsIdentitiesPage(
          api: NextermApi(baseUrl: 'https://host/api'),
          token: 't',
          loader: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Identities'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
  });

  testWidgets('Identities page lists identities', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsIdentitiesPage(
          api: NextermApi(baseUrl: 'https://host/api'),
          token: 't',
          loader: () async => const [
            Identity(
                id: 1, name: 'Prod key', type: 'ssh', username: 'root'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Prod key'), findsOneWidget);
    expect(find.text('root • ssh'), findsOneWidget);
  });

  testWidgets('Monitoring settings page loads values', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsMonitoringPage(
          api: NextermApi(baseUrl: 'https://host/api'),
          token: 't',
          loader: () async => const {
            'statusCheckerEnabled': true,
            'monitoringEnabled': false,
            'statusInterval': 60,
            'monitoringInterval': 120,
            'dataRetentionHours': 6,
            'connectionTimeout': 10,
            'batchSize': 10,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Collectors'), findsOneWidget);
    expect(find.text('Intervals & limits'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  test('parseSshConfig extracts hosts', () {
    const config = '''
# comment
Host example
  HostName 192.168.1.10
  User root
  Port 2222

Host *
  HostName ignored.example.com

Host nas
  HostName 192.168.1.30
''';
    final hosts = parseSshConfig(config);
    expect(hosts.length, 2);
    expect(hosts[0]['name'], 'example');
    expect(hosts[0]['ip'], '192.168.1.10');
    expect(hosts[0]['port'], 2222);
    expect(hosts[1]['name'], 'nas');
    expect(hosts[1]['port'], 22);
  });

  test('buildEntryPayload carries folder and extras', () {
    final payload = buildEntryPayload(
      name: 'DB',
      protocol: 'ssh',
      ip: '10.0.0.7',
      folderId: 3,
      includeFolder: true,
      configExtras: {'macAddress': 'AA:BB:CC:DD:EE:FF'},
    );
    expect(payload['folderId'], 3);
    expect((payload['config'] as Map)['macAddress'],
        'AA:BB:CC:DD:EE:FF');
    final plain = buildEntryPayload(
        name: 'X', protocol: 'rdp', ip: 'h');
    expect((plain as Map).containsKey('folderId'), isFalse);
  });

  testWidgets('API keys page shows empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsApiKeysPage(
          api: NextermApi(baseUrl: 'https://host/api'),
          token: 't',
          loader: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('API keys'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
  });

  testWidgets('API keys page lists keys', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsApiKeysPage(
          api: NextermApi(baseUrl: 'https://host/api'),
          token: 't',
          loader: () async => const [
            {'id': 7, 'name': 'CI token'},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('CI token'), findsOneWidget);
  });

  test('AppSettings persists theme mode', () async {
    final settings = await AppSettings.load();
    expect(settings.themeMode, ThemeMode.system);
    await settings.setThemeMode(ThemeMode.dark);
    final reloaded = await AppSettings.load();
    expect(reloaded.themeMode, ThemeMode.dark);
    await settings.setThemeMode(ThemeMode.system);
  });
}

List<MonitoredServer> _fakeMonitored() => [
      const MonitoredServer(
          id: '1',
          name: 'Webserver',
          ip: '192.168.1.10',
          port: 22,
          status: 'online',
          cpu: 23.5,
          mem: 61.2,
          load: 0.87,
          processes: 132,
          uptimeSeconds: 9000),
      const MonitoredServer(
          id: '3',
          name: 'NAS',
          ip: '192.168.1.30',
          status: 'online',
          cpu: 8.1,
          mem: 34.7),
      MonitoredServer(
          id: '2',
          name: 'Windows Box',
          ip: '192.168.1.20',
          status: 'offline',
          lastSeen:
              DateTime.now().subtract(const Duration(hours: 3))),
    ];

void _noop() {}

