import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/app_icons.dart';
import 'package:nexterm/widgets/floating_navigation_bar.dart';

const _destinations = [
  FloatingNavigationDestination(icon: AppIcons.dns, label: 'Servers'),
  FloatingNavigationDestination(
    icon: AppIcons.monitorMultiple,
    label: 'Sessions',
    badgeText: '3',
  ),
  FloatingNavigationDestination(
    icon: AppIcons.chartBoxOutline,
    label: 'Monitoring',
  ),
  FloatingNavigationDestination(icon: AppIcons.cog, label: 'Settings'),
];

void main() {
  testWidgets('renders destinations and marks the active one', (tester) async {
    await _pumpBar(tester, selectedIndex: 2);

    expect(find.byTooltip('Servers'), findsOneWidget);
    expect(find.byTooltip('Sessions'), findsOneWidget);
    expect(find.byTooltip('Monitoring'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    final monitoring = tester.getSemantics(find.bySemanticsLabel('Monitoring'));
    expect(monitoring.flagsCollection.isSelected, Tristate.isTrue);
    final servers = tester.getSemantics(find.bySemanticsLabel('Servers'));
    expect(servers.flagsCollection.isSelected, Tristate.isFalse);
  });

  testWidgets('tapping a destination reports it', (tester) async {
    int? selected;
    await _pumpBar(
      tester,
      selectedIndex: 0,
      onDestinationSelected: (index) => selected = index,
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();

    expect(selected, 3);
  });

  testWidgets('the indicator is a capsule, not a circle', (tester) async {
    await _pumpBar(tester, selectedIndex: 0);

    final indicator = tester.widget<Container>(
      find.byKey(FloatingNavigationBar.indicatorKey),
    );
    final decoration = indicator.decoration! as BoxDecoration;

    expect(decoration.shape, BoxShape.rectangle);
    expect(decoration.borderRadius, isNotNull);

    for (final container in tester.widgetList<Container>(
      find.descendant(
        of: find.byType(FloatingNavigationBar),
        matching: find.byType(Container),
      ),
    )) {
      final decoration = container.decoration;
      if (decoration is BoxDecoration) {
        expect(decoration.shape, isNot(BoxShape.circle));
      }
    }
  });

  testWidgets('dragging moves the capsule and selects on release', (
    tester,
  ) async {
    int? selected;
    await _pumpBar(
      tester,
      selectedIndex: 0,
      onDestinationSelected: (index) => selected = index,
    );

    final start = tester.getCenter(find.byTooltip('Servers'));
    final target = tester.getCenter(find.byTooltip('Monitoring'));
    final itemWidth = (target.dx - start.dx) / 2;
    final gesture = await tester.startGesture(start);
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy((target - start) / 8.0);
      await tester.pump();
    }

    // The capsule follows the finger, but the page only changes once the
    // gesture ends.
    expect(selected, isNull);
    final draggedCenter = tester
        .getCenter(find.byKey(FloatingNavigationBar.indicatorKey))
        .dx;
    expect((draggedCenter - target.dx).abs(), lessThan(itemWidth / 2));

    await gesture.up();
    await tester.pump();

    expect(selected, 2);
  });

  testWidgets('external selection changes animate the capsule', (tester) async {
    await _pumpBar(tester, selectedIndex: 0);

    await _pumpBar(tester, selectedIndex: 3);
    await tester.pump(const Duration(milliseconds: 350));

    final capsuleCenter = tester
        .getCenter(find.byKey(FloatingNavigationBar.indicatorKey))
        .dx;
    expect(
      capsuleCenter,
      closeTo(tester.getCenter(find.byTooltip('Settings')).dx, 2.0),
    );
  });

  testWidgets('badge text changes with a transition', (tester) async {
    await _pumpBar(tester, selectedIndex: 1);
    expect(find.text('3'), findsOneWidget);

    await _pumpBar(
      tester,
      selectedIndex: 1,
      destinations: const [
        FloatingNavigationDestination(icon: AppIcons.dns, label: 'Servers'),
        FloatingNavigationDestination(
          icon: AppIcons.monitorMultiple,
          label: 'Sessions · input',
          badgeText: '!',
          badgeIsAlert: true,
        ),
        FloatingNavigationDestination(
          icon: AppIcons.chartBoxOutline,
          label: 'Monitoring',
        ),
        FloatingNavigationDestination(icon: AppIcons.cog, label: 'Settings'),
      ],
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('!'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('reduced motion jumps directly to the selection', (tester) async {
    await _pumpBar(tester, selectedIndex: 0, disableAnimations: true);
    await _pumpBar(tester, selectedIndex: 3, disableAnimations: true);
    await tester.pump();

    final capsuleCenter = tester
        .getCenter(find.byKey(FloatingNavigationBar.indicatorKey))
        .dx;
    expect(
      capsuleCenter,
      closeTo(tester.getCenter(find.byTooltip('Settings')).dx, 2.0),
    );
  });
}

Future<void> _pumpBar(
  WidgetTester tester, {
  required int selectedIndex,
  List<FloatingNavigationDestination> destinations = _destinations,
  ValueChanged<int>? onDestinationSelected,
  bool disableAnimations = false,
}) async {
  final ValueChanged<int> onSelected = onDestinationSelected ?? (int _) {};
  final bar = FloatingNavigationBar(
    selectedIndex: selectedIndex,
    onDestinationSelected: onSelected,
    destinations: destinations,
  );

  await tester.pumpWidget(
    MaterialApp(
      home: disableAnimations
          ? MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(body: Center(child: bar)),
            )
          : Scaffold(body: Center(child: bar)),
    ),
  );
  await tester.pump();
}
