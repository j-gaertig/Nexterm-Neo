import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/widgets/nav_scope.dart';

void main() {
  testWidgets('pushed pages stay in the tab navigator and keep their state', (
    tester,
  ) async {
    final tabKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TabNavigator(
            navigatorKey: tabKey,
            builder: (context) => TextButton(
              onPressed: () => pushPage<void>(
                context,
                (_) => const Scaffold(body: Text('sub page')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    expect(tabKey.currentState!.canPop(), isFalse);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('sub page'), findsOneWidget);
    expect(tabKey.currentState!.canPop(), isTrue);

    // The shell pops one step when the active destination is tapped again.
    tabKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('sub page'), findsNothing);
    expect(tabKey.currentState!.canPop(), isFalse);
  });

  testWidgets('showNavBar: false covers the tab with a root page', (
    tester,
  ) async {
    final tabKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TabNavigator(
            navigatorKey: tabKey,
            builder: (context) => TextButton(
              onPressed: () => pushPage<void>(
                context,
                (_) => const Scaffold(body: Text('full screen')),
                showNavBar: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('full screen'), findsOneWidget);
    expect(tabKey.currentState!.canPop(), isFalse);
  });
}
