import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/server.dart';
import 'package:nexterm/screens/main_navigation_page.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('opens the monitoring tab when no sessions are active', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    final accountManager = ServerAccountManager();
    await accountManager.load();
    final themeManager = ThemeManager(ThemeMode.dark);
    final authManager = AuthManager(accountManager);
    final snippetManager = SnippetManager();
    final aiManager = AIManager();
    final sessionManager = SessionManager();
    final terminalSettings = await TerminalSettings.load();
    final sftpSettings = await SftpSettings.load();
    final serverViewSettings = await ServerViewSettings.load();
    final screenLockSettings = await ScreenLockSettings.load();
    final screenLockService = ScreenLockService();

    await tester.pumpWidget(
      MaterialApp(
        theme: themeManager.darkTheme(),
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
    );
    await tester.pump();

    // Without sessions there is no sessions destination, so index 1 is the
    // Monitoring tab and must be selectable.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Monitoring'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 1);
    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navigationBar.selectedIndex, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    themeManager.dispose();
    authManager.dispose();
    snippetManager.dispose();
    aiManager.dispose();
    sessionManager.dispose();
  });

  testWidgets('system back lets the active session handle navigation first', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    final accountManager = ServerAccountManager();
    await accountManager.load();
    final themeManager = ThemeManager(ThemeMode.dark);
    final authManager = AuthManager(accountManager);
    final snippetManager = SnippetManager();
    final aiManager = AIManager();
    final sessionManager = SessionManager();
    final session = AppSession(
      sessionId: 'sftp-session',
      server: const Server(name: 'Files', ip: '127.0.0.1'),
      type: ConnectionType.sftp,
    );
    sessionManager.seedSessionForTesting(session);
    final terminalSettings = await TerminalSettings.load();
    final sftpSettings = await SftpSettings.load();
    final serverViewSettings = await ServerViewSettings.load();
    final screenLockSettings = await ScreenLockSettings.load();
    final screenLockService = ScreenLockService();

    await tester.pumpWidget(
      MaterialApp(
        theme: themeManager.darkTheme(),
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
    );
    await tester.pump();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Sessions'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    // The sessions tab is fullscreen and has no bottom navigation bar.
    expect(find.byType(NavigationBar), findsNothing);

    var handled = false;
    session.handleBack = () {
      handled = true;
      return true;
    };
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(handled, isTrue);
    expect(find.byType(NavigationBar), findsNothing);
    expect(sessionManager.sessionCount, 1);

    session.handleBack = () => false;
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(sessionManager.sessionCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    themeManager.dispose();
    authManager.dispose();
    snippetManager.dispose();
    aiManager.dispose();
    sessionManager.dispose();
  });
}
