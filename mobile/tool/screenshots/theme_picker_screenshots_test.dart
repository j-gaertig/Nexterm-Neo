// Renders the compact appearance row and the palette gallery to PNGs.
//
// Run from the mobile/ directory:
//   flutter test tool/screenshots/theme_picker_screenshots_test.dart
//
// Override the output folder with SCREENSHOT_OUT (default:
// /tmp/opencode/nexterm-theme-picker).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/server_account.dart';
import 'package:nexterm/screens/settings_screen.dart';
import 'package:nexterm/services/screen_lock_service.dart';
import 'package:nexterm/utils/auth_manager.dart';
import 'package:nexterm/utils/screen_lock_settings.dart';
import 'package:nexterm/utils/server_account_manager.dart';
import 'package:nexterm/utils/server_view_settings.dart';
import 'package:nexterm/utils/sftp_settings.dart';
import 'package:nexterm/utils/terminal_settings.dart';
import 'package:nexterm/utils/theme_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _screenshotKey = ValueKey('theme-picker-screenshot');

void main() {
  final outputDir = Directory(
    Platform.environment['SCREENSHOT_OUT'] ??
        '/tmp/opencode/nexterm-theme-picker',
  );

  setUpAll(() async {
    await _loadPreviewFonts();
    outputDir.createSync(recursive: true);
  });

  testWidgets('renders the appearance row and palette gallery', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1170, 2532);
    debugDisableShadows = false;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      debugDisableShadows = true;
    });

    final manager = await _pumpSettings(tester, ThemeMode.dark);
    await _capture(tester, outputDir, 'appearance-dark');

    await tester.tap(find.byKey(const ValueKey('app-theme-picker')));
    await tester.pumpAndSettle();
    await _capture(tester, outputDir, 'gallery-dark');

    await tester.tap(find.byKey(const ValueKey('app-theme-tide')));
    await tester.pumpAndSettle();
    await _capture(tester, outputDir, 'gallery-tide-dark');

    await tester.tap(find.byKey(const ValueKey('theme-picker-close')));
    await tester.pumpAndSettle();
    manager.dispose();
    debugDisableShadows = true;
  });

  testWidgets('renders the palette gallery in light mode', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1170, 2532);
    debugDisableShadows = false;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      debugDisableShadows = true;
    });

    final manager = await _pumpSettings(tester, ThemeMode.light);
    await tester.tap(find.byKey(const ValueKey('app-theme-picker')));
    await tester.pumpAndSettle();
    await _capture(tester, outputDir, 'gallery-light');
    manager.dispose();
    debugDisableShadows = true;
  });
}

Future<ThemeManager> _pumpSettings(
  WidgetTester tester,
  ThemeMode themeMode,
) async {
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
      username: 'jane',
      fullName: 'Jane Doe',
    ),
  );
  await accountManager.switchAccount('preview-account');

  final authManager = AuthManager(accountManager);
  final themeManager = ThemeManager(themeMode);
  final terminalSettings = await TerminalSettings.load();
  final sftpSettings = await SftpSettings.load();
  final serverViewSettings = await ServerViewSettings.load();
  final screenLockSettings = await ScreenLockSettings.load();

  await tester.pumpWidget(
    RepaintBoundary(
      key: _screenshotKey,
      child: ListenableBuilder(
        listenable: themeManager,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: themeManager.lightTheme(),
          darkTheme: themeManager.darkTheme(),
          themeMode: themeManager.themeMode,
          home: SettingsScreen(
            themeManager: themeManager,
            authManager: authManager,
            terminalSettings: terminalSettings,
            sftpSettings: sftpSettings,
            serverViewSettings: serverViewSettings,
            screenLockSettings: screenLockSettings,
            screenLockService: ScreenLockService(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await Scrollable.ensureVisible(
    tester.element(find.byKey(const ValueKey('app-theme-picker'))),
    alignment: 0.45,
    duration: Duration.zero,
  );
  await tester.pumpAndSettle();

  return themeManager;
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
