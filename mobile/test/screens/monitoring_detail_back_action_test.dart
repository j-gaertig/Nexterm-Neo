import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexterm/models/server_account.dart';
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
  testWidgets('monitoring detail shows the back action beside the bar', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/monitoring')) {
        return http.Response(
          jsonEncode([
            {
              'id': 1,
              'name': 'prod-web-01',
              'ip': '10.20.0.11',
              'type': 'server',
              'status': 'online',
              'cpuUsage': 23.4,
              'memoryUsage': 41.8,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.contains('/monitoring/')) {
        return http.Response(
          jsonEncode({
            'latest': {
              'cpuUsage': 23.4,
              'memoryUsage': 41.8,
              'osInfo': {'hostname': 'prod-web-01'},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await http.runWithClient(() async {
      await _pumpMainNavigation(tester);

      await tester.tap(find.byTooltip('Monitoring'));
      await tester.pumpAndSettle();

      // The list view has no trailing action for monitoring.
      expect(find.byTooltip('Back'), findsNothing);

      await tester.tap(find.text('prod-web-01'));
      await tester.pumpAndSettle();

      // The detail view replaces the top-left back button with the action
      // next to the floating bar.
      expect(find.byTooltip('Back'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Back'), findsNothing);
      expect(find.text('prod-web-01'), findsOneWidget);
    }, () => client);
  });
}

Future<void> _pumpMainNavigation(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});

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

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    themeManager.dispose();
    authManager.dispose();
    snippetManager.dispose();
    aiManager.dispose();
    sessionManager.dispose();
    terminalSettings.dispose();
    sftpSettings.dispose();
    serverViewSettings.dispose();
    screenLockSettings.dispose();
  });
}
