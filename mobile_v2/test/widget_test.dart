import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexterm_v2/api/nexterm_api.dart';
import 'package:nexterm_v2/auth/session_store.dart';
import 'package:nexterm_v2/main.dart';
import 'package:nexterm_v2/screens/home_shell.dart';
import 'package:nexterm_v2/widgets/wobbly_nav_bar.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('normalizeBaseUrl hängt /api an und ergänzt https', () {
    expect(NextermApi.normalizeBaseUrl('nexterm.example.com'),
        'https://nexterm.example.com/api');
    expect(NextermApi.normalizeBaseUrl('http://host:6989/'),
        'http://host:6989/api');
    expect(NextermApi.normalizeBaseUrl('https://host/api'),
        'https://host/api');
    expect(NextermApi.normalizeBaseUrl('HTTPS://HOST/'),
        'HTTPS://HOST/api');
    expect(NextermApi.normalizeBaseUrl('https://host/API'),
        'https://host/API');
  });

  testWidgets('Login-Screen zeigt Server-URL-Feld', (tester) async {
    await tester.pumpWidget(const NextermApp());
    await tester.pumpAndSettle();
    expect(find.text('Server-URL'), findsOneWidget);
    expect(find.text('Verbinden'), findsOneWidget);
    expect(find.text('QR-Code scannen'), findsOneWidget);
  });

  testWidgets('HomeShell startet auf Home (Mitte)', (tester) async {
    const session = SessionInfo(
        token: 't', baseUrl: 'https://host/api', label: 'host');
    await tester.pumpWidget(
      const MaterialApp(home: HomeShell(session: session, onLogout: _noop)),
    );
    await tester.pumpAndSettle();
    // Navbar zeigt alle 5 Einträge, Home-Seite ist sichtbar.
    for (final label
        in ['Server', 'Monitoring', 'Home', 'Sonstiges', 'Einstellungen']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Verbunden mit host.'), findsOneWidget);
  });

  testWidgets('Tap auf Server wechselt die Seite', (tester) async {
    const session = SessionInfo(
        token: 't', baseUrl: 'https://host/api', label: 'host');
    await tester.pumpWidget(
      const MaterialApp(home: HomeShell(session: session, onLogout: _noop)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(WobblyNavBar),
      matching: find.text('Server'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Deine Server-Liste erscheint hier.'), findsOneWidget);
  });

  test('Apple-Glass nur auf iOS/macOS', () {
    expect(wobblyNavUsesAppleGlass(TargetPlatform.iOS), isTrue);
    expect(wobblyNavUsesAppleGlass(TargetPlatform.macOS), isTrue);
    expect(wobblyNavUsesAppleGlass(TargetPlatform.android), isFalse);
  });
}

void _noop() {}
