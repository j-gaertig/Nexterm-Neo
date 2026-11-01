import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/server_account.dart';
import 'package:nexterm/screens/server_accounts_screen.dart';
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

class _SettingsHarness {
  final ThemeManager themeManager;
  final AuthManager authManager;
  final SftpSettings sftpSettings;
  final ServerViewSettings serverViewSettings;
  final TerminalSettings terminalSettings;
  final ScreenLockSettings screenLockSettings;

  const _SettingsHarness({
    required this.themeManager,
    required this.authManager,
    required this.sftpSettings,
    required this.serverViewSettings,
    required this.terminalSettings,
    required this.screenLockSettings,
  });
}

Future<_SettingsHarness> _pumpSettings(
  WidgetTester tester, {
  Size size = const Size(390, 4200),
  ThemeMode themeMode = ThemeMode.dark,
  bool authenticated = true,
  String? username = 'jane',
  String? fullName = 'Jane Doe',
  double textScale = 1.0,
}) async {
  SharedPreferences.setMockInitialValues({});

  final accountManager = ServerAccountManager();
  await accountManager.load();
  if (authenticated) {
    await accountManager.addAccount(
      ServerAccount(
        id: 'test-account',
        label: 'Test',
        baseUrl: 'https://nexterm.example.com',
        token: 'test-token',
        username: username,
        fullName: fullName,
      ),
    );
    await accountManager.switchAccount('test-account');
  }

  final authManager = AuthManager(accountManager);
  final themeManager = ThemeManager(themeMode, useDynamicColor: false);
  final terminalSettings = await TerminalSettings.load();
  final sftpSettings = await SftpSettings.load();
  final serverViewSettings = await ServerViewSettings.load();
  final screenLockSettings = await ScreenLockSettings.load();
  final screenLockService = ScreenLockService();

  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: themeMode == ThemeMode.light
          ? themeManager.lightTheme()
          : themeManager.darkTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: SettingsScreen(
        themeManager: themeManager,
        authManager: authManager,
        terminalSettings: terminalSettings,
        sftpSettings: sftpSettings,
        serverViewSettings: serverViewSettings,
        screenLockSettings: screenLockSettings,
        screenLockService: screenLockService,
      ),
    ),
  );
  await tester.pump();

  return _SettingsHarness(
    themeManager: themeManager,
    authManager: authManager,
    sftpSettings: sftpSettings,
    serverViewSettings: serverViewSettings,
    terminalSettings: terminalSettings,
    screenLockSettings: screenLockSettings,
  );
}

void main() {
  testWidgets('orders the top-level settings sections', (tester) async {
    await _pumpSettings(tester);

    final sections = [
      'Account',
      'Security',
      'Appearance',
      'Terminal',
      'File Manager',
    ];
    final positions = [
      for (final section in sections) tester.getTopLeft(find.text(section)).dy,
    ];

    for (var i = 0; i < positions.length - 1; i++) {
      expect(
        positions[i],
        lessThan(positions[i + 1]),
        reason: '${sections[i]} should be above ${sections[i + 1]}',
      );
    }
  });

  testWidgets('uses the new labels and removes the old mixed labels', (
    tester,
  ) async {
    await _pumpSettings(tester);

    expect(find.text('Server Connections'), findsOneWidget);
    expect(find.text('Signed-in Devices'), findsOneWidget);
    expect(find.text('Authorize Login'), findsOneWidget);
    expect(find.text('Default View'), findsOneWidget);
    expect(find.text('Keyboard Toolbar'), findsOneWidget);
    expect(find.text('File Manager'), findsOneWidget);

    expect(find.text('File Browser'), findsNothing);
    expect(find.text('Scan QR Code'), findsNothing);
    expect(find.text('Connections'), findsNothing);
    expect(find.text('Sessions'), findsNothing);
  });

  testWidgets(
    'places Server List under Appearance and Keyboard Toolbar under Terminal',
    (tester) async {
      await _pumpSettings(tester);

      final appearance = tester.getTopLeft(find.text('Appearance')).dy;
      final serverList = tester.getTopLeft(find.text('Server List')).dy;
      final terminal = tester.getTopLeft(find.text('Terminal')).dy;
      final keyboardToolbar = tester
          .getTopLeft(find.text('Keyboard Toolbar'))
          .dy;
      final fileManager = tester.getTopLeft(find.text('File Manager')).dy;

      expect(appearance, lessThan(serverList));
      expect(serverList, lessThan(terminal));
      expect(terminal, lessThan(keyboardToolbar));
      expect(keyboardToolbar, lessThan(fileManager));
    },
  );

  testWidgets('shows dependent rows only when their parent is enabled', (
    tester,
  ) async {
    final harness = await _pumpSettings(tester);

    expect(find.text('Dim Hidden Files'), findsNothing);
    expect(find.text('Columns'), findsNothing);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Show Hidden Files'));
    await tester.pump();
    expect(harness.sftpSettings.showHiddenFiles, isTrue);
    expect(find.text('Dim Hidden Files'), findsOneWidget);

    await harness.serverViewSettings.setMode(ServerViewMode.grid);
    await tester.pump();
    expect(find.text('Columns'), findsOneWidget);

    await harness.serverViewSettings.setMode(ServerViewMode.list);
    await tester.pump();
    expect(find.text('Columns'), findsNothing);
  });

  testWidgets('keeps logout in the account card and can cancel it', (
    tester,
  ) async {
    await _pumpSettings(tester);

    expect(find.text('Logout'), findsOneWidget);
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();

    expect(find.text('Are you sure you want to logout?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Logout'), findsOneWidget);
  });

  testWidgets('signs out after confirming logout', (tester) async {
    final harness = await _pumpSettings(tester);

    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Logout'));
    await tester.pumpAndSettle();

    expect(harness.authManager.isAuthenticated, isFalse);
    expect(harness.authManager.accountManager.accounts, isEmpty);
  });

  testWidgets('keeps Server Connections reachable without a username', (
    tester,
  ) async {
    final harness = await _pumpSettings(tester, username: null, fullName: null);

    expect(harness.authManager.isAuthenticated, isTrue);
    expect(find.text('Server Connections'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
    expect(find.text('User'), findsOneWidget);
  });

  testWidgets('keeps Server Connections reachable without an account', (
    tester,
  ) async {
    await _pumpSettings(tester, authenticated: false);

    expect(find.text('Server Connections'), findsOneWidget);
    expect(find.text('Logout'), findsNothing);
    expect(find.text('User'), findsNothing);
  });

  testWidgets('opens Server Connections from the account card', (tester) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Server Connections'));
    await tester.pumpAndSettle();

    expect(find.byType(ServerAccountsScreen), findsOneWidget);
  });

  testWidgets('fits a 320dp-wide screen without overflow', (tester) async {
    await _pumpSettings(tester, size: const Size(320, 4200));

    expect(tester.takeException(), isNull);
    expect(find.text('File Manager'), findsOneWidget);
  });

  testWidgets('fits a 320dp-wide screen at large text scales', (tester) async {
    await _pumpSettings(tester, size: const Size(320, 6000), textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('File Manager'), findsOneWidget);
  });

  testWidgets('fits a 320dp-wide screen at extreme text scales', (
    tester,
  ) async {
    await _pumpSettings(tester, size: const Size(320, 6000), textScale: 3.0);

    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('File Manager'),
      400,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('settings-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('File Manager'), findsOneWidget);
  });

  testWidgets('terminal theme cards expose a semantics tap action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await _pumpSettings(tester);

      final node = tester.getSemantics(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Default terminal theme',
        ),
      );

      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('hides the iOS Files integration on non-iOS test platforms', (
    tester,
  ) async {
    await _pumpSettings(tester);

    expect(find.text('iOS Integration'), findsNothing);
    expect(find.text('Show in Files App'), findsNothing);
  });
}
