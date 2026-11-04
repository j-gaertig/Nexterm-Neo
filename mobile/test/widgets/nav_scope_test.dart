import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/widgets/floating_navigation_bar.dart';
import 'package:nexterm/widgets/nav_scope.dart';

void main() {
  testWidgets('pushed pages keep the floating bar and return to the tab', (
    tester,
  ) async {
    final controller = MainNavController()
      ..update(
        selectedIndex: 1,
        destinations: const [
          FloatingNavigationDestination(icon: Icons.dns, label: 'Servers'),
          FloatingNavigationDestination(
            icon: Icons.settings,
            label: 'Settings',
          ),
        ],
        onSelect: (_) {},
      );
    int? selected;
    controller.onSelect = (i) => selected = i;

    await tester.pumpWidget(
      MaterialApp(
        home: MainNavScope(
          controller: controller,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => pushPage<void>(
                  context,
                  (_) => const Scaffold(body: Text('sub page')),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(FloatingNavigationBar), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('sub page'), findsOneWidget);
    expect(find.byType(FloatingNavigationBar), findsOneWidget);

    await tester.tap(find.byTooltip('Servers').first);
    await tester.pumpAndSettle();

    expect(selected, 0);
    expect(find.text('sub page'), findsNothing);
  });

  testWidgets('pushPage without a scope shows a plain page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => pushPage<void>(
                context,
                (_) => const Scaffold(body: Text('plain')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('plain'), findsOneWidget);
    expect(find.byType(FloatingNavigationBar), findsNothing);
  });
}
