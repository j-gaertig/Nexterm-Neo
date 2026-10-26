import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/screens/screen_lock_screen.dart';
import 'package:nexterm/services/screen_lock_service.dart';

class _FakeScreenLockService extends ScreenLockService {
  _FakeScreenLockService(this.result);

  final ScreenLockAuthResult result;
  int authenticateCalls = 0;

  @override
  Future<ScreenLockAuthResult> authenticate({required String reason}) async {
    authenticateCalls++;
    return result;
  }
}

Future<_FakeScreenLockService> _pumpLockScreen(
  WidgetTester tester,
  ScreenLockAuthResult result, {
  VoidCallback? onUnlocked,
}) async {
  final service = _FakeScreenLockService(result);
  await tester.pumpWidget(
    MaterialApp(
      home: ScreenLockScreen(service: service, onUnlocked: onUnlocked ?? () {}),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  testWidgets('successful authentication reports unlock after auto prompt', (
    tester,
  ) async {
    var unlocked = false;
    final service = await _pumpLockScreen(
      tester,
      ScreenLockAuthResult.success,
      onUnlocked: () => unlocked = true,
    );

    expect(service.authenticateCalls, 1);
    expect(unlocked, isTrue);
  });

  testWidgets('canceling authentication keeps the lock screen open', (
    tester,
  ) async {
    final service = await _pumpLockScreen(
      tester,
      ScreenLockAuthResult.canceled,
    );

    expect(service.authenticateCalls, 1);
    expect(find.text('Nexterm is locked'), findsOneWidget);
    expect(find.text('Authentication was canceled.'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });

  testWidgets('unavailable authentication explains how to set up a screen lock', (
    tester,
  ) async {
    await _pumpLockScreen(tester, ScreenLockAuthResult.unavailable);

    expect(
      find.text(
        'Set up a screen lock (PIN, pattern, password, or biometrics) in your device settings and try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('system back cannot dismiss the lock screen', (tester) async {
    await _pumpLockScreen(tester, ScreenLockAuthResult.canceled);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Nexterm is locked'), findsOneWidget);
  });

  testWidgets('returning to the app prompts for authentication again', (
    tester,
  ) async {
    final service = await _pumpLockScreen(
      tester,
      ScreenLockAuthResult.canceled,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(service.authenticateCalls, 2);
    expect(find.text('Nexterm is locked'), findsOneWidget);
  });
}
