import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/services/session_manager.dart';
import 'package:nexterm/widgets/floating_navigation_bar.dart';
import 'package:nexterm/widgets/floating_navigation_scaffold.dart';
import 'package:nexterm/widgets/main_navigation_scope.dart';

void main() {
  testWidgets('shows the bar, inset, and back action on a pushed page', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);

    expect(find.text('Pushed page'), findsOneWidget);
    expect(find.byType(FloatingNavigationBar), findsOneWidget);
    expect(find.byTooltip('Servers'), findsOneWidget);
    expect(find.byTooltip('Monitoring'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);

    final inset = tester.widget<FloatingNavigationBarInset>(
      find.byType(FloatingNavigationBarInset),
    );
    expect(inset.bottom, FloatingNavigationBar.contentInset);
    expect(harness.controller.selectedIndex, 0);
  });

  testWidgets('keeps the bar above the keyboard on form pages', (tester) async {
    await _pumpHarness(tester);

    // FakeViewPadding is in physical pixels; at a device pixel ratio of 3 this
    // is a 300 logical pixel keyboard on the 600 pixel tall test surface.
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();

    expect(find.byType(FloatingNavigationBar), findsOneWidget);
    final surface = tester.getRect(
      find.byKey(FloatingNavigationBar.surfaceKey),
    );
    expect(surface.bottom, lessThanOrEqualTo(600 - 300));
  });

  testWidgets('a page-specific action replaces the back action', (
    tester,
  ) async {
    await _pumpHarness(
      tester,
      trailing: FloatingNavigationAction(
        icon: Icons.add,
        tooltip: 'Add',
        onPressed: () {},
      ),
    );

    expect(find.byTooltip('Add'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);

    final surface = tester.getRect(
      find.byKey(FloatingNavigationBar.surfaceKey),
    );
    final action = tester.getRect(find.byTooltip('Add'));
    expect(action.top, closeTo(surface.top, 0.5));
    expect(action.left, greaterThan(surface.right));
  });

  testWidgets('back action pops the pushed page', (tester) async {
    await _pumpHarness(tester);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Pushed page'), findsNothing);
    expect(find.text('Shell'), findsOneWidget);
    expect(find.byType(FloatingNavigationBar), findsNothing);
  });

  testWidgets('destination tap returns to the shell and selects the tab', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);

    await tester.tap(find.byTooltip('Monitoring'));
    await tester.pumpAndSettle();

    expect(find.text('Pushed page'), findsNothing);
    expect(find.text('Shell'), findsOneWidget);
    expect(harness.controller.selectedIndex, 1);
  });

  testWidgets('tapping the selected destination closes the pushed page', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);

    await tester.tap(find.byTooltip('Servers'));
    await tester.pumpAndSettle();

    expect(find.text('Pushed page'), findsNothing);
    expect(find.text('Shell'), findsOneWidget);
    expect(harness.controller.selectedIndex, 0);
  });

  testWidgets('without an enabled navigation scope the page keeps no bar', (
    tester,
  ) async {
    await _pumpHarness(tester, enabled: false);

    expect(find.text('Pushed page'), findsOneWidget);
    expect(find.byType(FloatingNavigationBar), findsNothing);
    expect(find.byTooltip('Back'), findsNothing);
    expect(
      tester
          .widget<FloatingNavigationBarInset>(
            find.byType(FloatingNavigationBarInset),
          )
          .bottom,
      0,
    );
  });
}

class _Harness {
  final MainNavigationController controller;
  final SessionManager sessionManager;

  const _Harness(this.controller, this.sessionManager);
}

Future<_Harness> _pumpHarness(
  WidgetTester tester, {
  bool enabled = true,
  Widget? trailing,
}) async {
  final controller = MainNavigationController();
  final sessionManager = SessionManager();
  addTearDown(() {
    controller.dispose();
    sessionManager.dispose();
  });

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MainNavigationScope(
        controller: controller,
        sessionManager: sessionManager,
        enabled: enabled,
        child: child ?? const SizedBox.shrink(),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Shell'),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FloatingNavigationScaffold(
                        trailing: trailing,
                        builder: _buildPushedPage,
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return _Harness(controller, sessionManager);
}

Widget _buildPushedPage(BuildContext context) {
  return ListView(
    padding: EdgeInsets.only(
      bottom: 24 + FloatingNavigationBarInset.of(context),
    ),
    children: const [Text('Pushed page')],
  );
}
