import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/script_runtime.dart';
import 'package:nexterm/models/server.dart';
import 'package:nexterm/screens/main_navigation_page.dart';
import 'package:nexterm/services/screen_lock_service.dart';
import 'package:nexterm/services/session_manager.dart';
import 'package:nexterm/utils/ai_manager.dart';
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
    final navigationBarSettings = await NavigationBarSettings.load();
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
          navigationBarSettings: navigationBarSettings,
          screenLockSettings: screenLockSettings,
          screenLockService: screenLockService,
        ),
      ),
    );
    await tester.pump();

    // The floating bar is the default. Without sessions there is no sessions
    // destination, so index 1 is the Monitoring tab and must be selectable.
    expect(find.byType(FloatingNavigationBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('Monitoring'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 1);
    final navigationBar = tester.widget<FloatingNavigationBar>(
      find.byType(FloatingNavigationBar),
    );
    expect(navigationBar.selectedIndex, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    themeManager.dispose();
    authManager.dispose();
    snippetManager.dispose();
    aiManager.dispose();
    sessionManager.dispose();
    navigationBarSettings.dispose();
  });

  testWidgets('switches between the floating and classic navigation bars', (
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
    final navigationBarSettings = await NavigationBarSettings.load();
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
          navigationBarSettings: navigationBarSettings,
          screenLockSettings: screenLockSettings,
          screenLockService: screenLockService,
        ),
      ),
    );
    await tester.pump();

    expect(navigationBarSettings.useFloating, isTrue);
    expect(find.byType(FloatingNavigationBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await navigationBarSettings.setUseFloating(false);
    await tester.pump();

    expect(find.byType(FloatingNavigationBar), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);

    await navigationBarSettings.setUseFloating(true);
    await tester.pump();

    expect(find.byType(FloatingNavigationBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    themeManager.dispose();
    authManager.dispose();
    snippetManager.dispose();
    aiManager.dispose();
    sessionManager.dispose();
    navigationBarSettings.dispose();
  });

  testWidgets('floating bar shows session badges and attention state', (
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
      sessionId: 'script-session',
      server: const Server(name: 'Build', ip: '127.0.0.1'),
      type: ConnectionType.sftp,
      scriptName: 'Deploy',
      scriptRuntime: const ScriptRuntimeState(
        scriptName: 'Deploy',
        status: ScriptSessionStatus.waitingForInput,
      ),
    );
    sessionManager.seedSessionForTesting(session);
    final terminalSettings = await TerminalSettings.load();
    final sftpSettings = await SftpSettings.load();
    final serverViewSettings = await ServerViewSettings.load();
    final navigationBarSettings = await NavigationBarSettings.load();
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
          navigationBarSettings: navigationBarSettings,
          screenLockSettings: screenLockSettings,
          screenLockService: screenLockService,
        ),
      ),
    );
    await tester.pump();

    final bar = tester.widget<FloatingNavigationBar>(
      find.byType(FloatingNavigationBar),
    );
    expect(bar.destinations, hasLength(4));
    expect(bar.destinations[1].label, 'Sessions · input');
    expect(bar.destinations[1].badgeText, '!');
    expect(bar.destinations[1].badgeIsAlert, isTrue);
    expect(find.text('!'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    themeManager.dispose();
    authManager.dispose();
    snippetManager.dispose();
    aiManager.dispose();
    sessionManager.dispose();
    navigationBarSettings.dispose();
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
    final navigationBarSettings = await NavigationBarSettings.load();
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
          navigationBarSettings: navigationBarSettings,
          screenLockSettings: screenLockSettings,
          screenLockService: screenLockService,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Sessions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    // The sessions tab is fullscreen and has no bottom navigation bar.
    expect(find.byType(FloatingNavigationBar), findsNothing);

    var handled = false;
    session.handleBack = () {
      handled = true;
      return true;
    };
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(handled, isTrue);
    expect(find.byType(FloatingNavigationBar), findsNothing);
    expect(sessionManager.sessionCount, 1);

    session.handleBack = () => false;
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(FloatingNavigationBar), findsOneWidget);
    expect(sessionManager.sessionCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    themeManager.dispose();
    authManager.dispose();
    snippetManager.dispose();
    aiManager.dispose();
    sessionManager.dispose();
    navigationBarSettings.dispose();
  });
}
