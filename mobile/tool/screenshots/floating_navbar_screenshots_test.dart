// Renders the floating navigation bar in its light, dark, badge, attention,
// drag, scrolled-content, and classic comparison states. Writes
// full-resolution PNGs to docs/pr-assets/floating-navbar-v2.
//
// Run from the mobile/ directory:
//   flutter test tool/screenshots/floating_navbar_screenshots_test.dart
//
// Optional environment variables:
//   SCREENSHOT_PREFIX  prefix for the generated file names (default: "nav")
//   SCREENSHOT_OUT     output directory (default: ../docs/pr-assets/floating-navbar-v2)

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexterm/models/server.dart';
import 'package:nexterm/models/server_account.dart';
import 'package:nexterm/screens/monitoring_screen.dart';
import 'package:nexterm/screens/servers_screen.dart';
import 'package:nexterm/screens/settings_screen.dart';
import 'package:nexterm/services/screen_lock_service.dart';
import 'package:nexterm/services/session_manager.dart';
import 'package:nexterm/utils/app_icons.dart';
import 'package:nexterm/utils/auth_manager.dart';
import 'package:nexterm/utils/navigation_bar_settings.dart';
import 'package:nexterm/utils/screen_lock_settings.dart';
import 'package:nexterm/utils/server_account_manager.dart';
import 'package:nexterm/utils/server_view_settings.dart';
import 'package:nexterm/utils/sftp_settings.dart';
import 'package:nexterm/utils/snippet_manager.dart';
import 'package:nexterm/utils/terminal_settings.dart';
import 'package:nexterm/utils/theme_manager.dart';
import 'package:nexterm/widgets/floating_navigation_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _screenshotKey = ValueKey('floating-navbar-screenshot');

void main() {
  final prefix = Platform.environment['SCREENSHOT_PREFIX'] ?? 'nav';
  final outputDir = Directory(
    Platform.environment['SCREENSHOT_OUT'] ??
        '../docs/pr-assets/floating-navbar-v2',
  );

  setUpAll(() async {
    await _loadPreviewFonts();
    outputDir.createSync(recursive: true);
  });

  testWidgets('renders floating navigation states', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.padding = const FakeViewPadding(bottom: 24);
    debugDisableShadows = false;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.view.resetPadding();
      debugDisableShadows = true;
    });

    await _pumpServersPreview(tester, themeMode: ThemeMode.dark);
    await _capture(tester, outputDir, '$prefix-dark-servers');

    await _pumpServersPreview(tester, themeMode: ThemeMode.dark, scrollBy: 80);
    await _capture(tester, outputDir, '$prefix-dark-servers-scrolled');

    await _pumpServersPreview(
      tester,
      themeMode: ThemeMode.dark,
      selectedIndex: 1,
      destinations: _destinations(sessionCount: 3),
      scrollBy: 60,
    );
    await _capture(tester, outputDir, '$prefix-dark-sessions');

    await _pumpServersPreview(
      tester,
      themeMode: ThemeMode.dark,
      selectedIndex: 1,
      destinations: _destinations(attention: true),
    );
    await _capture(tester, outputDir, '$prefix-dark-attention');

    await _pumpMonitoringPreview(
      tester,
      themeMode: ThemeMode.dark,
      destinations: _destinations(sessionCount: 3),
    );
    await _capture(tester, outputDir, '$prefix-dark-monitoring');

    await _pumpMonitoringPreview(
      tester,
      themeMode: ThemeMode.dark,
      destinations: _destinations(sessionCount: 3),
    );
    final drag = await _dragBar(
      tester,
      from: 'Monitoring',
      to: 'Settings',
      progress: 0.55,
    );
    await _capture(tester, outputDir, '$prefix-dark-dragging');
    await drag.up();
    await tester.pumpAndSettle();

    await _pumpServersPreview(tester, themeMode: ThemeMode.light, scrollBy: 80);
    await _capture(tester, outputDir, '$prefix-light-servers-scrolled');

    await _pumpSettingsPreview(tester, themeMode: ThemeMode.light);
    await _capture(tester, outputDir, '$prefix-light-settings');

    await _pumpClassicPreview(tester);
    await _capture(tester, outputDir, '$prefix-dark-classic');

    await _pumpSettingsPreview(
      tester,
      themeMode: ThemeMode.dark,
      scrollToAppearance: true,
    );
    await _capture(tester, outputDir, '$prefix-appearance-toggle');

    debugDisableShadows = true;
  });
}

List<FloatingNavigationDestination> _destinations({
  int sessionCount = 0,
  bool attention = false,
}) {
  return [
    const FloatingNavigationDestination(icon: AppIcons.dns, label: 'Servers'),
    if (sessionCount > 0 || attention)
      FloatingNavigationDestination(
        icon: AppIcons.monitorMultiple,
        label: attention ? 'Sessions · input' : 'Sessions',
        badgeText: attention ? '!' : '$sessionCount',
        badgeIsAlert: attention,
      ),
    const FloatingNavigationDestination(
      icon: AppIcons.chartBoxOutline,
      label: 'Monitoring',
    ),
    const FloatingNavigationDestination(icon: AppIcons.cog, label: 'Settings'),
  ];
}

/// Pumps the Servers page with the floating bar as a true overlay, matching
/// [MainNavigationPage]: content keeps the full height and scrolls behind the
/// bar, while [FloatingNavigationBarInset] reserves the last rows.
Future<void> _pumpServersPreview(
  WidgetTester tester, {
  required ThemeMode themeMode,
  int selectedIndex = 0,
  List<FloatingNavigationDestination>? destinations,
  bool classic = false,
  double scrollBy = 0,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({'folder_expanded_100': true});

  final accountManager = ServerAccountManager();
  await accountManager.load();
  await accountManager.addAccount(
    ServerAccount(
      id: 'preview-account',
      label: 'Preview',
      baseUrl: 'https://nexterm.example.com',
      token: 'preview-token',
    ),
  );
  await accountManager.switchAccount('preview-account');

  final authManager = AuthManager(accountManager);
  final snippetManager = SnippetManager();
  final sessionManager = SessionManager();
  final viewSettings = await ServerViewSettings.load();
  final themeManager = ThemeManager(themeMode, useDynamicColor: false);

  final serversScreen = ServersScreen(
    authManager: authManager,
    snippetManager: snippetManager,
    sessionManager: sessionManager,
    serverViewSettings: viewSettings,
    loadEntries: (_) async => _previewEntries(),
  );

  await tester.pumpWidget(
    RepaintBoundary(
      key: _screenshotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themeMode == ThemeMode.light
            ? themeManager.lightTheme()
            : themeManager.darkTheme(),
        home: classic
            ? Scaffold(
                body: serversScreen,
                bottomNavigationBar: NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (_) {},
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(AppIcons.dns),
                      label: 'Servers',
                    ),
                    NavigationDestination(
                      icon: Icon(AppIcons.chartBoxOutline),
                      label: 'Monitoring',
                    ),
                    NavigationDestination(
                      icon: Icon(AppIcons.cog),
                      label: 'Settings',
                    ),
                  ],
                ),
              )
            : Scaffold(
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    FloatingNavigationBarInset(
                      bottom: FloatingNavigationBar.contentInset,
                      child: serversScreen,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: FloatingNavigationBar(
                        selectedIndex: selectedIndex,
                        onDestinationSelected: (_) {},
                        destinations: destinations ?? _destinations(),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  if (scrollBy > 0) {
    // Scroll the list, not the bar: starting in the middle of the page also
    // demonstrates that the overlay no longer blocks the content underneath.
    await tester.drag(find.byType(ListView).last, Offset(0, -scrollBy));
    await tester.pumpAndSettle();
  }

  addTearDown(() {
    viewSettings.dispose();
    themeManager.dispose();
    authManager.dispose();
    snippetManager.dispose();
    sessionManager.dispose();
  });
}

/// Holds the capsule between two destinations and leaves the pointer down so
/// the screenshot shows the drag in progress. Release the returned gesture
/// after capturing.
Future<TestGesture> _dragBar(
  WidgetTester tester, {
  required String from,
  required String to,
  required double progress,
}) async {
  final start = tester.getCenter(find.byTooltip(from));
  final target = tester.getCenter(find.byTooltip(to));
  final gesture = await tester.startGesture(start);
  const steps = 24;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy((target - start) * (progress / steps));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 160));
  return gesture;
}

Future<void> _pumpClassicPreview(WidgetTester tester) async {
  await _pumpServersPreview(tester, themeMode: ThemeMode.dark, classic: true);
}

Future<void> _pumpSettingsPreview(
  WidgetTester tester, {
  required ThemeMode themeMode,
  bool scrollToAppearance = false,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});

  final accountManager = ServerAccountManager();
  await accountManager.load();
  await accountManager.addAccount(
    ServerAccount(
      id: 'preview-account',
      label: 'Preview',
      baseUrl: 'https://nexterm.example.com',
      token: 'preview-token',
      username: 'alex',
      fullName: 'Alex Rivera',
    ),
  );
  await accountManager.switchAccount('preview-account');

  final authManager = AuthManager(accountManager);
  final themeManager = ThemeManager(themeMode, useDynamicColor: false);
  final terminalSettings = await TerminalSettings.load();
  final sftpSettings = await SftpSettings.load();
  final viewSettings = await ServerViewSettings.load();
  final navigationBarSettings = await NavigationBarSettings.load();
  final screenLockSettings = await ScreenLockSettings.load();
  final screenLockService = ScreenLockService();

  await tester.pumpWidget(
    RepaintBoundary(
      key: _screenshotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themeMode == ThemeMode.light
            ? themeManager.lightTheme()
            : themeManager.darkTheme(),
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              FloatingNavigationBarInset(
                bottom: FloatingNavigationBar.contentInset,
                child: SettingsScreen(
                  themeManager: themeManager,
                  authManager: authManager,
                  terminalSettings: terminalSettings,
                  sftpSettings: sftpSettings,
                  serverViewSettings: viewSettings,
                  navigationBarSettings: navigationBarSettings,
                  screenLockSettings: screenLockSettings,
                  screenLockService: screenLockService,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: FloatingNavigationBar(
                  selectedIndex: 3,
                  onDestinationSelected: (_) {},
                  destinations: _destinations(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  if (scrollToAppearance) {
    await Scrollable.ensureVisible(
      tester.element(find.text('Floating Navigation Bar')),
      alignment: 0.38,
    );
    await tester.pumpAndSettle();
  }

  addTearDown(() {
    viewSettings.dispose();
    themeManager.dispose();
    authManager.dispose();
    terminalSettings.dispose();
    sftpSettings.dispose();
    navigationBarSettings.dispose();
    screenLockSettings.dispose();
  });
}

Future<void> _pumpMonitoringPreview(
  WidgetTester tester, {
  required ThemeMode themeMode,
  int selectedIndex = 2,
  List<FloatingNavigationDestination>? destinations,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});

  final accountManager = ServerAccountManager();
  await accountManager.load();
  await accountManager.addAccount(
    ServerAccount(
      id: 'preview-account',
      label: 'Preview',
      baseUrl: 'https://nexterm.example.com',
      token: 'preview-token',
    ),
  );
  await accountManager.switchAccount('preview-account');

  final authManager = AuthManager(accountManager);
  final themeManager = ThemeManager(themeMode, useDynamicColor: false);

  final client = MockClient((request) async {
    if (request.url.path.endsWith('/monitoring')) {
      return http.Response(
        jsonEncode(_monitoringEntries()),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404);
  });

  await http.runWithClient(() async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: _screenshotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: themeMode == ThemeMode.light
              ? themeManager.lightTheme()
              : themeManager.darkTheme(),
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                FloatingNavigationBarInset(
                  bottom: FloatingNavigationBar.contentInset,
                  child: MonitoringScreen(authManager: authManager),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: FloatingNavigationBar(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: (_) {},
                    destinations: destinations ?? _destinations(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }, () => client);

  addTearDown(() {
    themeManager.dispose();
    authManager.dispose();
  });
}

List<Map<String, dynamic>> _monitoringEntries() {
  return [
    {
      'id': 1,
      'name': 'prod-web-01',
      'ip': '10.20.0.11',
      'type': 'server',
      'status': 'online',
      'cpuUsage': 23.4,
      'memoryUsage': 41.8,
    },
    {
      'id': 2,
      'name': 'pve-node-01',
      'ip': '10.20.0.20',
      'type': 'proxmox',
      'status': 'online',
      'cpuUsage': 67.2,
      'memoryUsage': 72.5,
    },
    {
      'id': 3,
      'name': 'db-primary',
      'ip': '10.20.0.12',
      'type': 'server',
      'status': 'online',
      'cpuUsage': 84.6,
      'memoryUsage': 63.1,
    },
    {
      'id': 4,
      'name': 'backup-nas',
      'ip': '10.20.0.30',
      'type': 'server',
      'status': 'offline',
      'errorMessage': 'Agent unreachable',
    },
    {
      'id': 5,
      'name': 'edge-proxy-01',
      'ip': '10.20.0.5',
      'type': 'server',
      'status': 'online',
      'cpuUsage': 31.2,
      'memoryUsage': 28.7,
    },
    {
      'id': 6,
      'name': 'staging-api-01',
      'ip': '10.20.1.21',
      'type': 'server',
      'status': 'online',
      'cpuUsage': 12.8,
      'memoryUsage': 34.2,
    },
    {
      'id': 7,
      'name': 'media-vault',
      'ip': '10.20.0.40',
      'type': 'server',
      'status': 'online',
      'cpuUsage': 8.4,
      'memoryUsage': 55.6,
    },
    {
      'id': 8,
      'name': 'lab-worker-02',
      'ip': '10.20.2.12',
      'type': 'server',
      'status': 'online',
      'cpuUsage': 44.1,
      'memoryUsage': 61.3,
    },
  ];
}

Future<void> _capture(
  WidgetTester tester,
  Directory outputDir,
  String name,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screenshotKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('${outputDir.path}/$name.png');
    await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
  });
}

List<dynamic> _previewEntries() {
  return [
    Server.fromJson(
      _serverJson(
        id: 1,
        name: 'prod-web-01',
        ip: '10.20.0.11',
        protocol: 'ssh',
        status: 'online',
        tags: [_production, _web],
      ),
    ),
    Server.fromJson(
      _serverJson(
        id: 2,
        name: 'pve-node-01',
        ip: '10.20.0.20',
        type: 'pve-shell',
        status: 'running',
        tags: [_virtualization, _proxmox],
      ),
    ),
    Server.fromJson(
      _serverJson(
        id: 3,
        name: 'db-primary',
        ip: '10.20.0.12',
        protocol: 'ssh',
        status: 'online',
        tags: [_database],
      ),
    ),
    Server.fromJson(
      _serverJson(
        id: 4,
        name: 'backup-nas',
        ip: '10.20.0.30',
        protocol: 'sftp',
        status: 'offline',
        tags: [_storage, _backup],
      ),
    ),
    Server.fromJson(
      _serverJson(
        id: 5,
        name: 'edge-proxy-01',
        ip: '10.20.0.5',
        protocol: 'ssh',
        status: 'online',
        tags: [_production, _network],
      ),
    ),
    Server.fromJson(
      _serverJson(
        id: 6,
        name: 'staging-api-01',
        ip: '10.20.1.21',
        protocol: 'ssh',
        status: 'online',
        tags: [_staging, _web],
      ),
    ),
    Server.fromJson(
      _serverJson(
        id: 7,
        name: 'media-vault',
        ip: '10.20.0.40',
        protocol: 'sftp',
        status: 'online',
        tags: [_storage],
      ),
    ),
    Server.fromJson(
      _serverJson(
        id: 8,
        name: 'lab-worker-02',
        ip: '10.20.2.12',
        protocol: 'ssh',
        status: 'offline',
        tags: [_lab],
      ),
    ),
    Server.fromJson(
      _serverJson(
        id: 9,
        name: 'mail-relay-01',
        ip: '10.20.0.25',
        protocol: 'ssh',
        status: 'online',
        tags: [_production],
      ),
    ),
    Server.fromJson(
      _serverJson(
        id: 10,
        name: 'cache-redis-01',
        ip: '10.20.0.13',
        protocol: 'ssh',
        status: 'online',
        tags: [_database],
      ),
    ),
    Server.fromJson(
      _serverJson(
        id: 11,
        name: 'build-runner-03',
        ip: '10.20.3.33',
        protocol: 'ssh',
        status: 'online',
        tags: [_ci],
      ),
    ),
    Server.fromJson(
      _serverJson(
        id: 12,
        name: 'docs-mirror',
        ip: '10.20.4.8',
        protocol: 'sftp',
        status: 'offline',
        tags: [_staging],
      ),
    ),
  ];
}

Map<String, dynamic> _serverJson({
  required int id,
  required String name,
  required String ip,
  String? protocol,
  String? type,
  String? status,
  required List<Tag> tags,
}) {
  return {
    'id': id,
    'name': name,
    'ip': ip,
    'protocol': protocol,
    'type': type ?? 'server',
    'status': status,
    'tags': tags.map((tag) => tag.toJson()).toList(),
  };
}

const _production = Tag(id: 1, name: 'Production', color: '#22C55E');
const _web = Tag(id: 2, name: 'Web', color: '#3B82F6');
const _virtualization = Tag(id: 3, name: 'Virtualization', color: '#F59E0B');
const _proxmox = Tag(id: 4, name: 'Proxmox', color: '#F97316');
const _database = Tag(id: 5, name: 'Database', color: '#A855F7');
const _storage = Tag(id: 6, name: 'Storage', color: '#14B8A6');
const _backup = Tag(id: 7, name: 'Backup', color: '#64748B');
const _network = Tag(id: 8, name: 'Network', color: '#0EA5E9');
const _staging = Tag(id: 9, name: 'Staging', color: '#EC4899');
const _lab = Tag(id: 10, name: 'Lab', color: '#84CC16');
const _ci = Tag(id: 11, name: 'CI', color: '#8B5CF6');

Future<void> _loadPreviewFonts() async {
  final flutterRoot = _flutterRoot();
  final materialFonts = Directory(
    '$flutterRoot/bin/cache/artifacts/material_fonts',
  );
  final pubCache =
      Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['HOME']}/.pub-cache';
  final hosted = Directory('$pubCache/hosted/pub.dev');

  await (FontLoader('Roboto')
        ..addFont(_fontData(materialFonts, 'Roboto-Regular.ttf'))
        ..addFont(_fontData(materialFonts, 'Roboto-Medium.ttf'))
        ..addFont(_fontData(materialFonts, 'Roboto-Bold.ttf')))
      .load();

  await (FontLoader(
    'MaterialIcons',
  )..addFont(_fontData(materialFonts, 'MaterialIcons-Regular.otf'))).load();

  final lucide = _packageDir(hosted, 'lucide_icons_flutter');
  if (lucide != null) {
    await (FontLoader(
      'packages/lucide_icons_flutter/Lucide',
    )..addFont(_fontData(lucide, 'assets/lucide.ttf'))).load();
  }

  final mdi = _packageDir(hosted, 'flutter_material_design_icons');
  if (mdi != null) {
    await (FontLoader(
          'packages/flutter_material_design_icons/Material Design Icons',
        )..addFont(_fontData(mdi, 'assets/materialdesignicons-webfont.ttf')))
        .load();
  }
}

Directory? _packageDir(Directory hosted, String prefix) {
  if (!hosted.existsSync()) return null;
  final matches =
      hosted
          .listSync()
          .whereType<Directory>()
          .where((dir) => dir.path.split('/').last.startsWith(prefix))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return matches.isEmpty ? null : matches.last;
}

Future<ByteData> _fontData(Directory directory, String name) async {
  final bytes = await File('${directory.path}/$name').readAsBytes();
  return ByteData.view(bytes.buffer);
}

String _flutterRoot() {
  final fromEnv = Platform.environment['FLUTTER_ROOT'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  var file = File(Platform.resolvedExecutable).resolveSymbolicLinksSync();
  for (var i = 0; i < 5; i++) {
    file = File(file).parent.path;
  }
  return file;
}
