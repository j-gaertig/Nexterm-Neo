import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/app_icons.dart';
import 'package:nexterm/widgets/app_ui.dart';
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
  _extraTests();
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

  testWidgets('uses the T3 One UI dimensions and stays left-aligned', (
    tester,
  ) async {
    await _pumpBar(tester, selectedIndex: 0);

    final surface = tester.getRect(
      find.byKey(FloatingNavigationBar.surfaceKey),
    );
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;

    expect(surface.height, FloatingNavigationBar.barHeight);
    expect(surface.width, 4 * FloatingNavigationBar.itemExtent);
    expect(surface.left, FloatingNavigationBar.edgeMargin);
    expect(surface.right, lessThan(screenWidth / 2));

    final indicator = tester.getRect(
      find.byKey(FloatingNavigationBar.indicatorKey),
    );
    expect(indicator.height, FloatingNavigationBar.barHeight - 8);
    expect(indicator.width, FloatingNavigationBar.itemExtent - 8);

    final icon = tester.widget<Icon>(find.byIcon(AppIcons.dns));
    expect(icon.size, FloatingNavigationBar.iconSize);

    final cs = Theme.of(tester.element(find.byIcon(AppIcons.dns))).colorScheme;
    expect(icon.color, cs.primary);
    expect(
      tester.widget<Icon>(find.byIcon(AppIcons.chartBoxOutline)).color,
      cs.onSurface,
    );
  });

  testWidgets('a trailing action sits at the right at the same height', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      selectedIndex: 0,
      trailing: FloatingNavigationAction(
        icon: AppIcons.plus,
        tooltip: 'Add server',
        onPressed: () {},
      ),
    );

    final surface = tester.getRect(
      find.byKey(FloatingNavigationBar.surfaceKey),
    );
    final action = tester.getRect(find.byTooltip('Add server'));

    expect(action.top, surface.top);
    expect(action.height, surface.height);
    expect(action.width, FloatingNavigationBar.actionSize);
    expect(
      action.left - surface.right,
      greaterThanOrEqualTo(FloatingNavigationBar.actionGap),
    );

    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(
      action.right,
      closeTo(screenWidth - FloatingNavigationBar.edgeMargin, 0.5),
    );

    // The action carries the theme accent colour, stays elevated, and keeps
    // only slightly rounded corners.
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byTooltip('Add server'),
        matching: find.byType(Material),
      ),
    );
    final cs = Theme.of(
      tester.element(find.byTooltip('Add server')),
    ).colorScheme;
    // The add action uses a calmer, muted accent instead of the solid one.
    expect(material.color, mutedAccent(cs));
    expect(material.color, isNot(cs.primary));
    expect(tester.widget<Icon>(find.byIcon(AppIcons.plus)).color, cs.onSurface);
    expect(material.elevation, 6);
    expect(
      material.borderRadius,
      BorderRadius.circular(FloatingNavigationAction.radius),
    );
  });

  testWidgets('a third destination shrinks the bar instead of stretching it', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      selectedIndex: 0,
      destinations: _destinations.take(3).toList(),
    );

    final surface = tester.getRect(
      find.byKey(FloatingNavigationBar.surfaceKey),
    );
    expect(surface.width, 3 * FloatingNavigationBar.itemExtent);
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

void _extraTests() {
  testWidgets('tapping the selected destination reports it', (tester) async {
    var selectedTaps = 0;
    var changes = 0;
    await _pumpBar(
      tester,
      selectedIndex: 0,
      onSelectedTapped: () => selectedTaps++,
      onDestinationSelected: (_) => changes++,
    );

    await tester.tap(find.byTooltip(_destinations.first.label).first);
    await tester.pump();

    expect(selectedTaps, 1);
    expect(changes, 0);
  });

  testWidgets('the capsule follows the live swipe progress', (tester) async {
    final progress = ValueNotifier<double>(0);
    addTearDown(progress.dispose);
    await _pumpBar(tester, selectedIndex: 0, liveIndex: progress);

    final start = tester.getTopLeft(
      find.byKey(FloatingNavigationBar.indicatorKey),
    );
    progress.value = 0.5;
    await tester.pump();
    final half = tester.getTopLeft(
      find.byKey(FloatingNavigationBar.indicatorKey),
    );
    progress.value = 1;
    await tester.pump();
    final full = tester.getTopLeft(
      find.byKey(FloatingNavigationBar.indicatorKey),
    );

    expect(half.dx, greaterThan(start.dx));
    expect(full.dx, greaterThan(half.dx));
    expect(half.dx - start.dx, closeTo((full.dx - start.dx) / 2, 0.5));
  });
}

Future<void> _pumpBar(
  WidgetTester tester, {
  required int selectedIndex,
  List<FloatingNavigationDestination> destinations = _destinations,
  ValueChanged<int>? onDestinationSelected,
  bool disableAnimations = false,
  Widget? trailing,
  VoidCallback? onSelectedTapped,
  ValueListenable<double>? liveIndex,
}) async {
  final ValueChanged<int> onSelected = onDestinationSelected ?? (int _) {};
  final bar = FloatingNavigationBar(
    selectedIndex: selectedIndex,
    onDestinationSelected: onSelected,
    destinations: destinations,
    trailing: trailing,
    onSelectedDestinationTapped: onSelectedTapped,
    liveIndex: liveIndex,
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
