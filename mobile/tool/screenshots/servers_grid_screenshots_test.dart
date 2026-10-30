// Renders the Servers screen with deterministic preview data and writes
// full-resolution PNGs to docs/pr-assets/grid-view.
//
// Run from the mobile/ directory:
//   flutter test tool/screenshots/servers_grid_screenshots_test.dart
//
// Optional environment variables:
//   SCREENSHOT_PREFIX  prefix for the generated file names (default: "grid")
//   SCREENSHOT_OUT     output directory (default: ../docs/pr-assets/grid-view)

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/server.dart';
import 'package:nexterm/models/server_account.dart';
import 'package:nexterm/models/server_folder.dart';
import 'package:nexterm/screens/servers_screen.dart';
import 'package:nexterm/services/session_manager.dart';
import 'package:nexterm/utils/auth_manager.dart';
import 'package:nexterm/utils/server_account_manager.dart';
import 'package:nexterm/utils/server_view_settings.dart';
import 'package:nexterm/utils/snippet_manager.dart';
import 'package:nexterm/utils/theme_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _screenshotKey = ValueKey('servers-grid-screenshot');

void main() {
  final prefix = Platform.environment['SCREENSHOT_PREFIX'] ?? 'grid';
  final outputDir = Directory(
    Platform.environment['SCREENSHOT_OUT'] ?? '../docs/pr-assets/grid-view',
  );

  setUpAll(() async {
    await _loadPreviewFonts();
    outputDir.createSync(recursive: true);
  });

  testWidgets('renders grid preview variants', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1170, 2532);
    debugDisableShadows = false;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      debugDisableShadows = true;
    });

    await _pumpPreview(tester, themeMode: ThemeMode.dark, columns: 2);
    await _capture(tester, outputDir, '$prefix-dark-2col');

    await _pumpPreview(tester, themeMode: ThemeMode.light, columns: 2);
    await _capture(tester, outputDir, '$prefix-light-2col');

    await _pumpPreview(tester, themeMode: ThemeMode.dark, columns: 3);
    await _capture(tester, outputDir, '$prefix-dark-3col');

    debugDisableShadows = true;
  });
}

Future<void> _pumpPreview(
  WidgetTester tester, {
  required ThemeMode themeMode,
  required int columns,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({
    'server_view_mode': ServerViewMode.grid.name,
    'server_view_columns': columns,
    'folder_expanded_100': true,
  });

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

  await tester.pumpWidget(
    RepaintBoundary(
      key: _screenshotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themeMode == ThemeMode.light
            ? themeManager.lightTheme()
            : themeManager.darkTheme(),
        home: ServersScreen(
          authManager: authManager,
          snippetManager: snippetManager,
          sessionManager: sessionManager,
          serverViewSettings: viewSettings,
          loadEntries: (_) async => _previewEntries(),
        ),
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
  final homeLab = ServerFolder(
    id: 100,
    name: 'Home Lab',
    type: 'folder',
    position: 1,
    entries: [
      _serverJson(
        id: 3,
        name: 'db-primary',
        ip: '10.20.0.12',
        protocol: 'ssh',
        status: 'online',
        tags: [_production, _database],
      ),
      _serverJson(
        id: 4,
        name: 'backup-nas',
        ip: '10.20.0.30',
        protocol: 'sftp',
        status: 'offline',
        tags: [_storage, _backup],
      ),
      _serverJson(
        id: 5,
        name: 'win-jump',
        ip: '10.20.0.40',
        protocol: 'rdp',
        status: 'online',
        tags: [_windows, _bastion],
      ),
      _serverJson(
        id: 6,
        name: 'media-server',
        ip: '192.168.1.50',
        protocol: 'ssh',
        status: 'online',
        tags: [_media, _home],
      ),
      _serverJson(
        id: 7,
        name: 'home-assistant',
        ip: '192.168.1.60',
        protocol: 'ssh',
        status: 'offline',
        tags: [_home, _iot],
      ),
      _serverJson(
        id: 8,
        name: 'pi-hole',
        ip: '192.168.1.53',
        protocol: 'ssh',
        status: 'online',
        tags: [_dns, _home],
      ),
    ],
  );

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
    homeLab,
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
const _windows = Tag(id: 8, name: 'Windows', color: '#0EA5E9');
const _bastion = Tag(id: 9, name: 'Bastion', color: '#EF4444');
const _media = Tag(id: 10, name: 'Media', color: '#EC4899');
const _home = Tag(id: 11, name: 'Home', color: '#8B5CF6');
const _iot = Tag(id: 12, name: 'IoT', color: '#F97316');
const _dns = Tag(id: 13, name: 'DNS', color: '#06B6D4');

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
