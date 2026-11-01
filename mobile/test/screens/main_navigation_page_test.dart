import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kterm/kterm.dart';
import 'package:nexterm/models/script_runtime.dart';
import 'package:nexterm/models/server.dart';
import 'package:nexterm/screens/main_navigation_page.dart';
import 'package:nexterm/screens/sessions_overview_screen.dart';
import 'package:nexterm/screens/widgets/session_grid_card.dart';
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

  testWidgets('shows the add action next to the bar only on the servers tab', (
    tester,
  ) async {
    await _pumpMainNavigation(tester);

    final addAction = find.byTooltip('Add server');
    expect(addAction, findsOneWidget);

    final surface = tester.getRect(
      find.byKey(FloatingNavigationBar.surfaceKey),
    );
    final action = tester.getRect(addAction);
    expect(action.top, closeTo(surface.top, 0.5));
    expect(action.height, surface.height);
    expect(action.left, greaterThan(surface.right));
    expect(find.byTooltip('Close all sessions'), findsNothing);

    await tester.tap(find.byTooltip('Monitoring'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Add server'), findsNothing);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Add server'), findsNothing);

    await tester.tap(find.byTooltip('Servers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Add server'), findsOneWidget);
  });

  testWidgets(
    'shows the close-all action next to the bar on the sessions tab',
    (tester) async {
      await _pumpMainNavigation(
        tester,
        session: AppSession(
          sessionId: 'sftp-session',
          server: const Server(name: 'Files', ip: '127.0.0.1'),
          type: ConnectionType.sftp,
        ),
      );

      expect(find.byTooltip('Close all sessions'), findsNothing);

      await tester.tap(find.byTooltip('Sessions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final closeAll = find.byTooltip('Close all sessions');
      expect(closeAll, findsOneWidget);
      expect(find.byTooltip('Add server'), findsNothing);

      // The close-all action uses the solid error colour so it reads as
      // destructive next to the accent-coloured add action.
      final closeAllMaterial = tester.widget<Material>(
        find.descendant(of: closeAll, matching: find.byType(Material)),
      );
      expect(
        closeAllMaterial.color,
        Theme.of(tester.element(closeAll)).colorScheme.error,
      );

      final surface = tester.getRect(
        find.byKey(FloatingNavigationBar.surfaceKey),
      );
      final action = tester.getRect(closeAll);
      expect(action.top, closeTo(surface.top, 0.5));
      expect(action.left, greaterThan(surface.right));
    },
  );

  testWidgets('swipes between top-level pages and stops at the edges', (
    tester,
  ) async {
    await _pumpMainNavigation(tester);

    // Servers is the first page, so swiping right must keep it in place.
    await _swipeMainPage(tester, 300);
    expect(tester.widget<TabCrossfade>(find.byType(TabCrossfade)).index, 0);

    // Without sessions, swiping left moves from Servers to Monitoring.
    await _swipeMainPage(tester, -300);
    expect(tester.widget<TabCrossfade>(find.byType(TabCrossfade)).index, 1);

    // Monitoring is in the middle and moves in both directions.
    await _swipeMainPage(tester, -300);
    expect(tester.widget<TabCrossfade>(find.byType(TabCrossfade)).index, 2);

    // Settings is the last page, so swiping left must keep it in place.
    await _swipeMainPage(tester, -300);
    expect(tester.widget<TabCrossfade>(find.byType(TabCrossfade)).index, 2);

    await _swipeMainPage(tester, 300);
    expect(tester.widget<TabCrossfade>(find.byType(TabCrossfade)).index, 1);
  });

  testWidgets('swipes through the sessions destination in both directions', (
    tester,
  ) async {
    await _pumpMainNavigation(
      tester,
      session: AppSession(
        sessionId: 'sftp-session',
        server: const Server(name: 'Files', ip: '127.0.0.1'),
        type: ConnectionType.sftp,
      ),
    );

    await _swipeMainPage(tester, -300);
    expect(tester.widget<TabCrossfade>(find.byType(TabCrossfade)).index, 1);

    await _swipeMainPage(tester, -300);
    expect(tester.widget<TabCrossfade>(find.byType(TabCrossfade)).index, 2);

    await _swipeMainPage(tester, 300);
    expect(tester.widget<TabCrossfade>(find.byType(TabCrossfade)).index, 1);

    await _swipeMainPage(tester, 300);
    expect(tester.widget<TabCrossfade>(find.byType(TabCrossfade)).index, 0);
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

  testWidgets('sessions tab always starts on the full-screen overview', (
    tester,
  ) async {
    await _pumpMainNavigation(
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

    expect(find.byType(SessionsOverviewScreen), findsOneWidget);
    expect(find.byType(SessionGridCard), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('SFTP'), findsOneWidget);
    // The overview behaves like every other top-level page.
    expect(find.byType(FloatingNavigationBar), findsOneWidget);
  });

  testWidgets('system back returns from a session to the overview first', (
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
    await tester.tap(find.byKey(const ValueKey('session-card-sftp-session')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The session is fullscreen and has no bottom navigation bar.
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
    await tester.pumpAndSettle();

    // Back from the session shows the overview, not the servers tab.
    expect(find.byType(SessionsOverviewScreen), findsOneWidget);
    expect(find.byType(FloatingNavigationBar), findsOneWidget);
    expect(
      tester
          .widget<FloatingNavigationBar>(find.byType(FloatingNavigationBar))
          .selectedIndex,
      1,
    );
    expect(harness.sessionManager.sessionCount, 1);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester
          .widget<FloatingNavigationBar>(find.byType(FloatingNavigationBar))
          .selectedIndex,
      0,
    );
  });

  testWidgets('keyboard inset is applied once on the sessions tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpMainNavigation(
      tester,
      session: AppSession(
        sessionId: 'terminal-session',
        server: const Server(name: 'Shell', ip: '127.0.0.1'),
        type: ConnectionType.terminal,
        terminal: Terminal(maxLines: 100),
      ),
    );

    await tester.tap(find.byTooltip('Sessions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey('session-card-terminal-session')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final terminal = find.byType(TerminalView);
    expect(tester.getRect(terminal).height, 800);

    // A tall One UI keyboard (380 logical px) must shrink the page exactly
    // once. The sessions page has its own Scaffold below the navigation
    // Scaffold, so a re-applied MediaQuery used to subtract the keyboard
    // height twice and collapse the terminal to a single line.
    tester.view.viewInsets = const FakeViewPadding(bottom: 1140);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.getRect(terminal).height, 420);
  });
}

Future<void> _swipeMainPage(WidgetTester tester, double dx) async {
  final center = tester.getCenter(find.byType(TabCrossfade));
  final gesture = await tester.startGesture(center);
  for (var i = 0; i < 4; i++) {
    await gesture.moveBy(Offset(dx / 4, 0));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
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

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    themeManager.dispose();
    authManager.dispose();
    snippetManager.dispose();
    aiManager.dispose();
    sessionManager.dispose();
  });

  return _MainNavigationHarness(sessionManager: sessionManager);
}

class _MainNavigationHarness {
  final SessionManager sessionManager;

  const _MainNavigationHarness({required this.sessionManager});
}
