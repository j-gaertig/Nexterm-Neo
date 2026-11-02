// Renders full-screen pages that are pushed above the navigation shell. Each
// page keeps the floating bar and moves its own action next to it instead of
// showing a top-left back button. The server connections page shows its add
// action there; the other pages show their back action.
//
// Run from the mobile/ directory:
//   flutter test tool/screenshots/full_page_nav_screenshots_test.dart
//
// Optional environment variables:
//   SCREENSHOT_PREFIX  prefix for the generated file names (default: "full-nav")
//   SCREENSHOT_OUT     output directory (default: ../docs/pr-assets/full-page-nav)

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexterm/models/server_account.dart';
import 'package:nexterm/screens/main_navigation_page.dart';
import 'package:nexterm/screens/server_accounts_screen.dart';
import 'package:nexterm/screens/sessions_screen.dart';
import 'package:nexterm/services/screen_lock_service.dart';
import 'package:nexterm/services/session_manager.dart';
import 'package:nexterm/utils/ai_manager.dart';
import 'package:nexterm/utils/auth_manager.dart';
import 'package:nexterm/utils/screen_lock_settings.dart';
import 'package:nexterm/utils/server_account_manager.dart';
import 'package:nexterm/utils/server_view_settings.dart';
import 'package:nexterm/utils/sftp_settings.dart';
import 'package:nexterm/utils/snippet_manager.dart';
import 'package:nexterm/utils/terminal_settings.dart';
import 'package:nexterm/utils/theme_manager.dart';
import 'package:nexterm/widgets/main_navigation_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _screenshotKey = ValueKey('full-page-nav-screenshot');

void main() {
  final prefix = Platform.environment['SCREENSHOT_PREFIX'] ?? 'full-nav';
  final outputDir = Directory(
    Platform.environment['SCREENSHOT_OUT'] ?? '../docs/pr-assets/full-page-nav',
  );

  setUpAll(() async {
    await _loadPreviewFonts();
    outputDir.createSync(recursive: true);
  });

  testWidgets('renders full-screen pages with the floating navigation', (
    tester,
  ) async {
    _configureView(tester);

    final accountManager = await _previewAccountManager();
    final authManager = AuthManager(accountManager);

    await _pumpPushedPage(
      tester,
      themeMode: ThemeMode.dark,
      pageBuilder: (_) => ServerAccountsScreen(authManager: authManager),
    );
    expect(find.byTooltip('Add server'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    await _capture(tester, outputDir, '$prefix-dark-server-connections');

    await _pumpPushedPage(
      tester,
      themeMode: ThemeMode.light,
      pageBuilder: (_) => ServerAccountsScreen(authManager: authManager),
    );
    await _capture(tester, outputDir, '$prefix-light-server-connections');

    final sessionsClient = MockClient((request) async {
      if (request.url.path.endsWith('/sessions/list')) {
        return http.Response(
          jsonEncode(_sessionEntries()),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await http.runWithClient(() async {
      await _pumpPushedPage(
        tester,
        themeMode: ThemeMode.dark,
        pageBuilder: (_) => SessionsScreen(authManager: authManager),
      );
      await _capture(tester, outputDir, '$prefix-dark-signed-in-devices');
    }, () => sessionsClient);

    authManager.dispose();
    _resetView(tester);
  });

  testWidgets('renders the monitoring back action in the floating bar', (
    tester,
  ) async {
    _configureView(tester);

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/monitoring')) {
        return http.Response(
          jsonEncode(_monitoringEntries()),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.contains('/monitoring/')) {
        return http.Response(
          jsonEncode(_monitoringDetails()),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await http.runWithClient(() async {
      await _pumpMainNavigation(tester, themeMode: ThemeMode.dark);
      await tester.tap(find.byTooltip('Monitoring'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('prod-web-01'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.byTooltip('Add server'), findsNothing);
      await _capture(tester, outputDir, '$prefix-dark-monitoring-detail');
    }, () => client);

    await tester.pumpWidget(const SizedBox.shrink());
    _resetView(tester);
  });
}

void _configureView(WidgetTester tester) {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.padding = const FakeViewPadding(bottom: 24);
  debugDisableShadows = false;
}

void _resetView(WidgetTester tester) {
  tester.view.resetDevicePixelRatio();
  tester.view.resetPhysicalSize();
  tester.view.resetPadding();
  debugDisableShadows = true;
}

Future<void> _pumpPushedPage(
  WidgetTester tester, {
  required ThemeMode themeMode,
  required WidgetBuilder pageBuilder,
}) async {
  final controller = MainNavigationController();
  final sessionManager = SessionManager();
  final themeManager = ThemeManager(themeMode);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    RepaintBoundary(
      key: _screenshotKey,
      child: MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: themeMode == ThemeMode.light
            ? themeManager.lightTheme()
            : themeManager.darkTheme(),
        builder: (context, child) => MainNavigationScope(
          controller: controller,
          sessionManager: sessionManager,
          enabled: true,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: pageBuilder)),
                child: const Text('Open page'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open page'));
  await tester.pumpAndSettle();

  addTearDown(() {
    themeManager.dispose();
    controller.dispose();
    sessionManager.dispose();
  });
}

Future<void> _pumpMainNavigation(
  WidgetTester tester, {
  required ThemeMode themeMode,
}) async {
  SharedPreferences.setMockInitialValues({});

  final accountManager = await _previewAccountManager();
  final authManager = AuthManager(accountManager);
  final themeManager = ThemeManager(themeMode);
  final snippetManager = SnippetManager();
  final aiManager = AIManager();
  final sessionManager = SessionManager();
  final terminalSettings = await TerminalSettings.load();
  final sftpSettings = await SftpSettings.load();
  final serverViewSettings = await ServerViewSettings.load();
  final screenLockSettings = await ScreenLockSettings.load();
  final screenLockService = ScreenLockService();

  await tester.pumpWidget(
    RepaintBoundary(
      key: _screenshotKey,
      child: MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: themeMode == ThemeMode.light
            ? themeManager.lightTheme()
            : themeManager.darkTheme(),
        home: MainNavigationPage(
          themeManager: themeManager,
          authManager: authManager,
          snippetManager: snippetManager,
          aiManager: aiManager,
          sessionManager: sessionManager,
          terminalSettings: terminalSettings,
          sftpSettings: sftpSettings,
          serverViewSettings: serverViewSettings,
          screenLockSettings: screenLockSettings,
          screenLockService: screenLockService,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  addTearDown(() {
    themeManager.dispose();
    authManager.dispose();
    snippetManager.dispose();
    aiManager.dispose();
    sessionManager.dispose();
    terminalSettings.dispose();
    sftpSettings.dispose();
    serverViewSettings.dispose();
    screenLockSettings.dispose();
  });
}

Future<ServerAccountManager> _previewAccountManager() async {
  SharedPreferences.setMockInitialValues({});

  final accountManager = ServerAccountManager();
  await accountManager.load();
  await accountManager.addAccount(
    ServerAccount(
      id: 'preview-account',
      label: 'Nexterm Cloud',
      baseUrl: 'https://nexterm.example.com',
      token: 'preview-token',
      username: 'alex',
      fullName: 'Alex Rivera',
    ),
  );
  await accountManager.addAccount(
    ServerAccount(
      id: 'homelab-account',
      label: 'Homelab',
      baseUrl: 'https://homelab.example.com',
      token: 'preview-token-2',
      username: 'alex',
      fullName: 'Alex Rivera',
    ),
  );
  await accountManager.switchAccount('preview-account');
  return accountManager;
}

List<Map<String, dynamic>> _sessionEntries() {
  final now = DateTime.now();
  return [
    {
      'id': 'current-session',
      'userAgent': 'NextermMobile/1.2.2 (android)',
      'ip': '10.20.0.42',
      'createdAt': now.subtract(const Duration(hours: 2)).toIso8601String(),
      'lastActivity': now.toIso8601String(),
      'current': true,
    },
    {
      'id': 'browser-session',
      'userAgent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/131.0 Safari/537.36',
      'ip': '10.20.0.18',
      'createdAt': now.subtract(const Duration(days: 1)).toIso8601String(),
      'lastActivity': now
          .subtract(const Duration(minutes: 12))
          .toIso8601String(),
      'current': false,
    },
    {
      'id': 'connector-session',
      'userAgent': 'NextermConnector/1.0.4 (linux; x64)',
      'ip': '10.20.0.9',
      'createdAt': now.subtract(const Duration(days: 3)).toIso8601String(),
      'lastActivity': now.subtract(const Duration(hours: 5)).toIso8601String(),
      'current': false,
    },
  ];
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
  ];
}

Map<String, dynamic> _monitoringDetails() {
  final now = DateTime.now();
  return {
    'latest': {
      'timestamp': now.toIso8601String(),
      'cpuUsage': 23.4,
      'memoryUsage': 41.8,
      'processes': 184,
      'loadAverage': [0.42, 0.55, 0.61],
      'uptime': 196430,
      'osInfo': {
        'hostname': 'prod-web-01',
        'name': 'Ubuntu 24.04.1 LTS',
        'version': '6.8.0-45-generic',
        'kernel': '6.8.0-45-generic',
        'architecture': 'x86_64',
      },
    },
  };
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
