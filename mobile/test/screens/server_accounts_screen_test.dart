import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/server_account.dart';
import 'package:nexterm/screens/device_setup_screen.dart';
import 'package:nexterm/screens/server_accounts_screen.dart';
import 'package:nexterm/services/session_manager.dart';
import 'package:nexterm/utils/app_icons.dart';
import 'package:nexterm/utils/auth_manager.dart';
import 'package:nexterm/utils/server_account_manager.dart';
import 'package:nexterm/widgets/floating_navigation_bar.dart';
import 'package:nexterm/widgets/main_navigation_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('moves the add action next to the floating bar', (tester) async {
    await _pumpServerAccounts(tester);

    expect(find.text('Server Connections'), findsOneWidget);
    expect(find.byType(FloatingNavigationBar), findsOneWidget);

    // The header no longer carries its own add button. The only plus action
    // is the one next to the bar.
    expect(find.byIcon(AppIcons.plus), findsOneWidget);
    final addAction = find.byTooltip('Add server');
    expect(addAction, findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);

    final surface = tester.getRect(
      find.byKey(FloatingNavigationBar.surfaceKey),
    );
    final action = tester.getRect(addAction);
    expect(action.top, closeTo(surface.top, 0.5));
    expect(action.height, surface.height);
    expect(action.left, greaterThan(surface.right));
  });

  testWidgets('add action opens the add-server page with the bar', (
    tester,
  ) async {
    await _pumpServerAccounts(tester);

    await tester.tap(find.byTooltip('Add server'));
    await tester.pumpAndSettle();

    expect(find.byType(DeviceSetupScreen), findsOneWidget);
    expect(find.text('Add Server'), findsOneWidget);
    expect(find.byType(FloatingNavigationBar), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('tapping a destination returns to the top-level shell', (
    tester,
  ) async {
    final controller = await _pumpServerAccounts(tester);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Server Connections'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(controller.selectedIndex, 2);
  });
}

Future<MainNavigationController> _pumpServerAccounts(
  WidgetTester tester,
) async {
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
  await accountManager.switchAccount('preview-account');

  final authManager = AuthManager(accountManager);
  final controller = MainNavigationController();
  final sessionManager = SessionManager();

  addTearDown(() {
    authManager.dispose();
    accountManager.dispose();
    controller.dispose();
    sessionManager.dispose();
  });

  await tester.pumpWidget(
    MaterialApp(
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
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ServerAccountsScreen(authManager: authManager),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  return controller;
}
