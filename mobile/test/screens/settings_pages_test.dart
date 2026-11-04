import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/server_account.dart';
import 'package:nexterm/screens/settings/pages/about_page.dart';
import 'package:nexterm/screens/settings/pages/account_page.dart';
import 'package:nexterm/screens/settings/pages/admin_pages.dart';
import 'package:nexterm/screens/settings/pages/api_keys_page.dart';
import 'package:nexterm/screens/settings/pages/identities_page.dart';
import 'package:nexterm/screens/settings/ui.dart';
import 'package:nexterm/services/account_service.dart';
import 'package:nexterm/utils/app_icons.dart';
import 'package:nexterm/utils/auth_manager.dart';
import 'package:nexterm/utils/server_account_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AuthManager> _auth() async {
  SharedPreferences.setMockInitialValues({});
  final accounts = ServerAccountManager();
  await accounts.load();
  await accounts.addAccount(
    ServerAccount(
      id: 'a',
      label: 'Test',
      baseUrl: 'https://nexterm.example.com',
      token: 'token',
      username: 'jane',
      fullName: 'Jane Doe',
    ),
  );
  await accounts.switchAccount('a');
  return AuthManager(accounts);
}

void main() {
  group('AccountProfile', () {
    test('parses the /accounts/me response', () {
      final p = AccountProfile.fromJson({
        'id': 3,
        'username': 'jane',
        'firstName': 'Jane',
        'lastName': 'Doe',
        'totpEnabled': true,
        'isAdmin': false,
        'permissions': ['settings.monitoring', 'users.view'],
        'sessionSync': 'same_tab',
      });
      expect(p.displayName, 'Jane Doe');
      expect(p.totpEnabled, isTrue);
      expect(p.sessionSync, 'same_tab');
      expect(p.can('settings.monitoring'), isTrue);
      expect(p.can('settings.engines'), isFalse);
      expect(p.hasAnyAdminAccess, isTrue);
    });

    test('admins can do everything; plain users get no admin access', () {
      final admin = AccountProfile.fromJson({
        'id': 1,
        'username': 'root',
        'isAdmin': true,
      });
      expect(admin.can('settings.engines'), isTrue);
      final user = AccountProfile.fromJson({'id': 2, 'username': 'u'});
      expect(user.displayName, 'u');
      expect(user.hasAnyAdminAccess, isFalse);
    });
  });

  test('MonitoringSettings round-trips and copies', () {
    final s = MonitoringSettings.fromJson({
      'statusInterval': 45,
      'monitoringEnabled': false,
      'dataRetentionHours': 12,
    });
    expect(s.statusInterval, 45);
    expect(s.monitoringEnabled, isFalse);
    expect(s.batchSize, 10);
    final changed = s.copyWith(batchSize: 20);
    expect(changed.toJson()['batchSize'], 20);
    expect(changed.toJson()['dataRetentionHours'], 12);
  });

  test('ApiKeyInfo keeps the one-time token only when present', () {
    final created = ApiKeyInfo.fromJson({
      'id': 1,
      'name': 'ci',
      'prefix': 'nxt_ab12…',
      'token': 'nxt_secret',
    });
    expect(created.token, 'nxt_secret');
    final listed = ApiKeyInfo.fromJson({'id': 2, 'name': 'x', 'prefix': 'p'});
    expect(listed.token, isNull);
  });

  testWidgets('SettingsGroup renders tiles with dividers and a footer', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsGroup(
            title: 'Group',
            footer: 'Footer text',
            children: [
              SettingsTile(
                icon: AppIcons.key,
                title: 'One',
                subtitle: 'first',
                onTap: () => tapped++,
              ),
              SettingsSwitchTile(
                icon: AppIcons.lockOutline,
                title: 'Two',
                value: true,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Group'), findsOneWidget);
    expect(find.text('Footer text'), findsOneWidget);
    await tester.tap(find.text('One'));
    expect(tapped, 1);
    expect(find.byType(Switch), findsOneWidget);
  });

  group('pages explain failures instead of staying empty', () {
    Future<void> pump(
      WidgetTester tester,
      Widget Function(AuthManager) page,
    ) async {
      final auth = await _auth();
      await tester.pumpWidget(MaterialApp(home: page(auth)));
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    testWidgets('account', (tester) async {
      await pump(tester, (a) => AccountPage(authManager: a));
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('API keys', (tester) async {
      await pump(tester, (a) => ApiKeysPage(authManager: a));
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('API keys'), findsOneWidget);
    });

    testWidgets('identities', (tester) async {
      await pump(tester, (a) => IdentitiesPage(authManager: a));
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('engines, users and monitoring', (tester) async {
      await pump(tester, (a) => EnginesPage(authManager: a));
      expect(find.text('Retry'), findsOneWidget);
      await pump(tester, (a) => UsersPage(authManager: a));
      expect(find.text('Retry'), findsOneWidget);
      await pump(tester, (a) => MonitoringSettingsPage(authManager: a));
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  testWidgets('about page shows the app version and links', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pump();
    expect(find.text('Nexterm Neo'), findsWidgets);
    expect(find.text('Open-source licenses'), findsOneWidget);
    expect(find.text('Nexterm Neo on GitHub'), findsOneWidget);
  });
}
