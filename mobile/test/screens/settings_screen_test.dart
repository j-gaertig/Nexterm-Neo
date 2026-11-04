import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/server_account.dart';
import 'package:nexterm/screens/server_accounts_screen.dart';
import 'package:nexterm/screens/settings_screen.dart';
import 'package:nexterm/services/screen_lock_service.dart';
import 'package:nexterm/utils/app_themes.dart';
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
  final themeManager = ThemeManager(themeMode);
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

Future<void> _open(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('orders the settings groups', (tester) async {
    await _pumpSettings(tester);

    final groups = ['Account', 'Preferences', 'Security', 'Library', 'About'];
    final positions = [
      for (final g in groups) tester.getTopLeft(find.text(g).first).dy,
    ];
    for (var i = 0; i < positions.length - 1; i++) {
      expect(
        positions[i],
        lessThan(positions[i + 1]),
        reason: '${groups[i]} should be above ${groups[i + 1]}',
      );
    }
  });

  testWidgets('lists every top-level destination', (tester) async {
    await _pumpSettings(tester);

    for (final title in const [
      'API keys',
      'Signed-in devices',
      'Authorize login',
      'Server connections',
      'Appearance',
      'Terminal',
      'File manager',
      'Screen lock',
      'Identities',
      'About Nexterm Neo',
      'Sign out',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    // Administration only appears for users with the matching permissions.
    expect(find.text('Administration'), findsNothing);
    expect(find.text('Engines'), findsNothing);
  });

  testWidgets('shows the profile card with the signed-in user', (tester) async {
    await _pumpSettings(tester);

    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.textContaining('@jane'), findsOneWidget);
  });

  testWidgets('search narrows the list and explains empty results', (
    tester,
  ) async {
    await _pumpSettings(tester);

    await tester.enterText(find.byType(TextField), 'font');
    await tester.pump();
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('Appearance'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();
    expect(find.text('No settings found'), findsOneWidget);
  });

  testWidgets('keeps sign out reachable and can cancel it', (tester) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Are you sure you want to logout?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('signs out after confirming', (tester) async {
    final harness = await _pumpSettings(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Logout'));
    await tester.pumpAndSettle();

    expect(harness.authManager.isAuthenticated, isFalse);
    expect(harness.authManager.accountManager.accounts, isEmpty);
  });

  testWidgets('keeps Server connections reachable without a username', (
    tester,
  ) async {
    final harness = await _pumpSettings(tester, username: null, fullName: null);

    expect(harness.authManager.isAuthenticated, isTrue);
    expect(find.text('Server connections'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('User'), findsOneWidget);
  });

  testWidgets('hides sign out without an account', (tester) async {
    await _pumpSettings(tester, authenticated: false);

    expect(find.text('Server connections'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('opens Server connections', (tester) async {
    await _pumpSettings(tester);

    await _open(tester, 'Server connections');

    expect(find.byType(ServerAccountsScreen), findsOneWidget);
  });

  testWidgets('fits a 320dp-wide screen without overflow', (tester) async {
    await _pumpSettings(tester, size: const Size(320, 4200));

    expect(tester.takeException(), isNull);
    expect(find.text('About Nexterm Neo'), findsOneWidget);
  });

  testWidgets('fits a 320dp-wide screen at extreme text scales', (
    tester,
  ) async {
    await _pumpSettings(tester, size: const Size(320, 6000), textScale: 3.0);

    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('About Nexterm Neo'),
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
    expect(find.text('About Nexterm Neo'), findsOneWidget);
  });

  group('appearance page', () {
    testWidgets('puts Server List under Appearance', (tester) async {
      await _pumpSettings(tester);
      await _open(tester, 'Appearance');

      expect(find.text('Default View'), findsOneWidget);
      final themes = tester.getTopLeft(find.text('Themes')).dy;
      final serverList = tester.getTopLeft(find.text('Server List')).dy;
      expect(themes, lessThan(serverList));
    });

    testWidgets('shows the column count only in grid view', (tester) async {
      final harness = await _pumpSettings(tester);
      await _open(tester, 'Appearance');

      expect(find.text('Columns'), findsNothing);

      await harness.serverViewSettings.setMode(ServerViewMode.grid);
      await tester.pump();
      expect(find.text('Columns'), findsOneWidget);

      await harness.serverViewSettings.setMode(ServerViewMode.list);
      await tester.pump();
      expect(find.text('Columns'), findsNothing);
    });

    testWidgets('opens a compact palette gallery and applies a theme', (
      tester,
    ) async {
      final harness = await _pumpSettings(tester);
      await _open(tester, 'Appearance');

      expect(find.text('Themes'), findsOneWidget);
      expect(find.byKey(const ValueKey('app-theme-picker')), findsOneWidget);
      expect(AppThemes.all.map((theme) => theme.label), [
        'Graphite',
        'Adaptive',
        'Blossom',
        'Meadow',
        'Tide',
        'Copper',
        'Aurora',
      ]);
      expect(find.byKey(const ValueKey('app-theme-graphite')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('app-theme-picker')));
      await tester.pumpAndSettle();

      final sheet = find.byKey(const ValueKey('theme-picker-sheet'));
      expect(sheet, findsOneWidget);
      for (final theme in AppThemes.all) {
        expect(
          find.descendant(of: sheet, matching: find.text(theme.label)),
          findsOneWidget,
        );
      }

      await tester.tap(find.byKey(const ValueKey('app-theme-blossom')));
      await tester.pumpAndSettle();
      expect(harness.themeManager.theme.id, 'blossom');

      await tester.tap(find.byKey(const ValueKey('theme-picker-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('theme-picker-sheet')), findsNothing);
    });
  });

  group('terminal page', () {
    testWidgets('puts Keyboard Toolbar under Terminal', (tester) async {
      await _pumpSettings(tester, size: const Size(390, 4200));
      await _open(tester, 'Terminal');

      expect(find.text('Keyboard Toolbar'), findsOneWidget);
      expect(find.text('Terminal Theme'), findsOneWidget);
    });

    testWidgets('terminal theme cards expose a semantics tap action', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await _pumpSettings(tester);
        await _open(tester, 'Terminal');

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
  });

  group('file manager page', () {
    testWidgets('shows dependent rows only when their parent is enabled', (
      tester,
    ) async {
      final harness = await _pumpSettings(tester);
      await _open(tester, 'File manager');

      expect(find.text('Dim Hidden Files'), findsNothing);

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Show Hidden Files'),
      );
      await tester.pump();
      expect(harness.sftpSettings.showHiddenFiles, isTrue);
      expect(find.text('Dim Hidden Files'), findsOneWidget);
    });

    testWidgets('hides the iOS Files integration on other platforms', (
      tester,
    ) async {
      await _pumpSettings(tester);
      await _open(tester, 'File manager');

      expect(find.text('iOS Integration'), findsNothing);
      expect(find.text('Show in Files App'), findsNothing);
    });
  });
}
