import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/app_icons.dart';
import 'package:nexterm/widgets/app_ui.dart';

void main() {
  testWidgets('shows only the active tab label and no filled indicator', (
    tester,
  ) async {
    final controller = TabController(length: 2, vsync: const TestVSync());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppIconTabBar(
            controller: controller,
            tabs: const [
              AppTabItem(label: 'Overview', icon: AppIcons.monitor),
              AppTabItem(label: 'Charts', icon: AppIcons.chartBoxOutline),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Charts'), findsNothing);
    expect(find.byIcon(AppIcons.monitor), findsOneWidget);
    expect(find.byIcon(AppIcons.chartBoxOutline), findsOneWidget);

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect((tabBar.indicator! as BoxDecoration).color, Colors.transparent);

    controller.animateTo(1);
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsNothing);
    expect(find.text('Charts'), findsOneWidget);
  });

  testWidgets('fits three tabs with a long active label on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TabController(
      length: 3,
      initialIndex: 1,
      vsync: const TestVSync(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AppIconTabBar(
              controller: controller,
              tabs: const [
                AppTabItem(label: 'Details', icon: AppIcons.pencilOutline),
                AppTabItem(
                  label: 'Identities',
                  icon: AppIcons.accountCircleOutline,
                ),
                AppTabItem(label: 'Settings', icon: AppIcons.cogOutline),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Identities'), findsOneWidget);
    expect(find.text('Details'), findsNothing);
  });
}
