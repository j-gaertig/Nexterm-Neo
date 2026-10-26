import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/server_account.dart';
import 'package:nexterm/services/screen_lock_service.dart';
import 'package:nexterm/utils/auth_manager.dart';
import 'package:nexterm/utils/screen_lock_coordinator.dart';
import 'package:nexterm/utils/screen_lock_settings.dart';
import 'package:nexterm/utils/server_account_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingScreenLockService extends ScreenLockService {
  int authenticateCalls = 0;

  @override
  Future<ScreenLockAuthResult> authenticate({required String reason}) async {
    authenticateCalls++;
    return ScreenLockAuthResult.failed;
  }

  @override
  Future<void> cancel() async {}
}

class _Harness {
  _Harness({
    required this.settings,
    required this.accountManager,
    required this.authManager,
    required this.service,
    required this.coordinator,
    required this.navigatorKey,
  });

  final ScreenLockSettings settings;
  final ServerAccountManager accountManager;
  final AuthManager authManager;
  final _FailingScreenLockService service;
  final ScreenLockCoordinator coordinator;
  final GlobalKey<NavigatorState> navigatorKey;

  void dispose() {
    coordinator.dispose();
    authManager.dispose();
    settings.dispose();
  }
}

ServerAccount _account() {
  return ServerAccount(
    id: 'account-1',
    label: 'Test',
    baseUrl: 'https://example.com',
    token: 'token',
    username: 'tester',
  );
}

Future<_Harness> _pumpCoordinator(
  WidgetTester tester, {
  required bool authenticated,
  bool enabled = true,
}) async {
  SharedPreferences.setMockInitialValues({'screen_lock_enabled': enabled});
  final settings = await ScreenLockSettings.load();
  final accountManager = ServerAccountManager();
  final authManager = AuthManager(accountManager);
  final service = _FailingScreenLockService();
  final navigatorKey = GlobalKey<NavigatorState>();
  final coordinator = ScreenLockCoordinator(
    navigatorKey: navigatorKey,
    settings: settings,
    authManager: authManager,
    service: service,
  );

  if (authenticated) {
    await accountManager.addAccount(_account());
    await accountManager.switchAccount('account-1');
  }

  coordinator.start();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('App content')),
    ),
  );
  await tester.pumpAndSettle();

  final harness = _Harness(
    settings: settings,
    accountManager: accountManager,
    authManager: authManager,
    service: service,
    coordinator: coordinator,
    navigatorKey: navigatorKey,
  );
  addTearDown(harness.dispose);
  return harness;
}

void main() {
  testWidgets('signing in after logout shows the lock screen', (tester) async {
    final harness = await _pumpCoordinator(tester, authenticated: false);

    await harness.accountManager.addAccount(_account());
    await harness.accountManager.switchAccount('account-1');
    await tester.pumpAndSettle();

    expect(find.text('Nexterm is locked'), findsOneWidget);
    expect(harness.service.authenticateCalls, 1);
  });

  testWidgets('startup with an authenticated account shows the lock screen', (
    tester,
  ) async {
    await _pumpCoordinator(tester, authenticated: true);

    expect(find.text('Nexterm is locked'), findsOneWidget);
  });

  testWidgets('an unrelated pop cannot dismiss the lock screen', (
    tester,
  ) async {
    final harness = await _pumpCoordinator(tester, authenticated: true);

    harness.navigatorKey.currentState!.pop(true);
    await tester.pumpAndSettle();

    expect(find.text('Nexterm is locked'), findsOneWidget);
  });

  testWidgets(
    'enabling the setting while backgrounded shows the lock on return',
    (tester) async {
      final harness = await _pumpCoordinator(
        tester,
        authenticated: true,
        enabled: false,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await harness.settings.setEnabled(true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Nexterm is locked'), findsOneWidget);
    },
  );

  testWidgets('disabling the setting dismisses the lock screen', (
    tester,
  ) async {
    final harness = await _pumpCoordinator(tester, authenticated: true);

    await harness.settings.setEnabled(false);
    await tester.pumpAndSettle();

    expect(find.text('Nexterm is locked'), findsNothing);
    expect(find.text('App content'), findsOneWidget);
  });
}
