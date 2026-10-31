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
import 'package:nexterm/widgets/tab_crossfade.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('opens the monitoring tab when no sessions are active', (
    tester,
  ) async {
    await _pumpMainNavigation(tester);

    // The floating bar is the default. Without sessions there is no sessions
    // destination, so index 1 is the Monitoring tab and must be selectable.
    expect(find.byType(FloatingNavigationBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('Monitoring'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final crossfade = tester.widget<TabCrossfade>(find.byType(TabCrossfade));
    expect(crossfade.index, 1);
    final navigationBar = tester.widget<FloatingNavigationBar>(
      find.byType(FloatingNavigationBar),
    );
    expect(navigationBar.selectedIndex, 1);
  });

  testWidgets('floating bar overlays the page instead of reserving space', (
    tester,
  ) async {
    await _pumpMainNavigation(tester);

    final outerScaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(outerScaffold.bottomNavigationBar, isNull);
    expect(
      find.byKey(const ValueKey('floating-navigation-overlay')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('floating-navigation-overlay')),
        matching: find.byType(FloatingNavigationBar),
      ),
      findsOneWidget,
    );

    final inset = tester.widget<FloatingNavigationBarInset>(
      find.byType(FloatingNavigationBarInset),
    );
    expect(inset.bottom, FloatingNavigationBar.contentInset);
  });

  testWidgets('dragging the selection capsule switches tabs', (tester) async {
    await _pumpMainNavigation(tester);

    final start = tester.getCenter(find.byTooltip('Servers'));
    final target = tester.getCenter(find.byTooltip('Settings'));
    final gesture = await tester.startGesture(start);
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy((target - start) / 8.0);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final crossfade = tester.widget<TabCrossfade>(find.byType(TabCrossfade));
    expect(crossfade.index, 2);
    final navigationBar = tester.widget<FloatingNavigationBar>(
      find.byType(FloatingNavigationBar),
    );
    expect(navigationBar.selectedIndex, 2);
  });

  testWidgets('switches between the floating and classic navigation bars', (
    tester,
  ) async {
    final harness = await _pumpMainNavigation(tester);

    expect(harness.navigationBarSettings.useFloating, isTrue);
    expect(find.byType(FloatingNavigationBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.byKey(const ValueKey('floating-navigation-overlay')),
      findsOneWidget,
    );

    await harness.navigationBarSettings.setUseFloating(false);
    await tester.pump();

    expect(find.byType(FloatingNavigationBar), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      find.byKey(const ValueKey('floating-navigation-overlay')),
      findsNothing,
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar,
      isNotNull,
    );

    await harness.navigationBarSettings.setUseFloating(true);
    await tester.pump();

    expect(find.byType(FloatingNavigationBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('floating bar shows session badges and attention state', (
    tester,
  ) async {
    await _pumpMainNavigation(
      tester,
      session: AppSession(
        sessionId: 'script-session',
        server: const Server(name: 'Build', ip: '127.0.0.1'),
        type: ConnectionType.sftp,
        scriptName: 'Deploy',
        scriptRuntime: const ScriptRuntimeState(
          scriptName: 'Deploy',
          status: ScriptSessionStatus.waitingForInput,
        ),
      ),
    );

    final bar = tester.widget<FloatingNavigationBar>(
      find.byType(FloatingNavigationBar),
    );
    expect(bar.destinations, hasLength(4));
    expect(bar.destinations[1].label, 'Sessions · input');
    expect(bar.destinations[1].badgeText, '!');
    expect(bar.destinations[1].badgeIsAlert, isTrue);
    expect(find.text('!'), findsOneWidget);
  });

  testWidgets('keeps the logical tab when sessions appear', (tester) async {
    final harness = await _pumpMainNavigation(tester);

    await tester.tap(find.byTooltip('Monitoring'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<TabCrossfade>(find.byType(TabCrossfade)).index, 1);

    harness.sessionManager.seedSessionForTesting(
      AppSession(
        sessionId: 'sftp-session',
        server: const Server(name: 'Files', ip: '127.0.0.1'),
        type: ConnectionType.sftp,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Monitoring moved from index 1 to index 2, but it must stay selected.
    expect(tester.widget<TabCrossfade>(find.byType(TabCrossfade)).index, 2);
    expect(
      tester
          .widget<FloatingNavigationBar>(find.byType(FloatingNavigationBar))
          .selectedIndex,
      2,
    );
  });

  testWidgets('system back lets the active session handle navigation first', (
    tester,
  ) async {
    final harness = await _pumpMainNavigation(
      tester,
      session: AppSession(
        sessionId: 'sftp-session',
        server: const Server(name: 'Files', ip: '127.0.0.1'),
        type: ConnectionType.sftp,
      ),
    );

    await tester.tap(find.byTooltip('Sessions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The sessions tab is fullscreen and has no bottom navigation bar.
    expect(find.byType(FloatingNavigationBar), findsNothing);

    var handled = false;
    final session = harness.sessionManager.activeSession!;
    session.handleBack = () {
      handled = true;
      return true;
    };
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(handled, isTrue);
    expect(find.byType(FloatingNavigationBar), findsNothing);
    expect(harness.sessionManager.sessionCount, 1);

    session.handleBack = () => false;
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FloatingNavigationBar), findsOneWidget);
    expect(harness.sessionManager.sessionCount, 1);
  });
}

Future<_MainNavigationHarness> _pumpMainNavigation(
  WidgetTester tester, {
  AppSession? session,
}) async {
  SharedPreferences.setMockInitialValues({});

  final accountManager = ServerAccountManager();
  await accountManager.load();
  final themeManager = ThemeManager(ThemeMode.dark);
  final authManager = AuthManager(accountManager);
  final snippetManager = SnippetManager();
  final aiManager = AIManager();
  final sessionManager = SessionManager();
  if (session != null) sessionManager.seedSessionForTesting(session);
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

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    themeManager.dispose();
    authManager.dispose();
    snippetManager.dispose();
    aiManager.dispose();
    sessionManager.dispose();
    navigationBarSettings.dispose();
  });

  return _MainNavigationHarness(
    sessionManager: sessionManager,
    navigationBarSettings: navigationBarSettings,
  );
}

class _MainNavigationHarness {
  final SessionManager sessionManager;
  final NavigationBarSettings navigationBarSettings;

  const _MainNavigationHarness({
    required this.sessionManager,
    required this.navigationBarSettings,
  });
}
