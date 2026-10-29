import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/server.dart';
import 'package:nexterm/screens/widgets/server_actions_sheet.dart';
import 'package:nexterm/utils/app_icons.dart';

const _server = Server(
  id: 1,
  name: 'web-01',
  ip: '10.0.0.1',
  protocol: 'ssh',
  type: 'server',
  identities: [7],
  wakeOnLanEnabled: true,
  macAddress: 'AA:BB:CC:DD:EE:FF',
);

const _labels = [
  'Connect',
  'Run Script',
  'Quick Connect',
  'Wake-On-LAN',
  'Edit',
  'Duplicate',
  'Disable',
  'Delete',
];

late BuildContext _hostContext;

Future<void> _pumpHost(
  WidgetTester tester, {
  Size size = const Size(360, 800),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            _hostContext = context;
            return const Center(child: Text('Host'));
          },
        ),
      ),
    ),
  );
}

List<ServerAction> _actions(List<String> tapped) => [
  for (final label in _labels)
    ServerAction(
      icon: AppIcons.connection,
      label: label,
      onTap: () => tapped.add(label),
    ),
];

Future<void> _openSheet(WidgetTester tester, List<String> tapped) async {
  showServerActionsSheet(
    _hostContext,
    _server,
    icon: AppIcons.brandServer,
    actions: _actions(tapped),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ServerActionsSheet', () {
    testWidgets('scrolls so every action stays reachable on a short screen', (
      tester,
    ) async {
      await _pumpHost(tester, size: const Size(320, 480));
      final tapped = <String>[];
      await _openSheet(tester, tapped);

      final scrollable = find.byType(Scrollable);
      expect(scrollable, findsOneWidget);

      final sheetHeight = tester.getSize(find.byType(ServerActionsSheet)).height;
      expect(sheetHeight, lessThanOrEqualTo(480 * 0.85));

      final scrollableState = tester.state<ScrollableState>(scrollable);
      expect(scrollableState.position.maxScrollExtent, greaterThan(0));

      await tester.drag(scrollable, const Offset(0, -200));
      await tester.pump();
      expect(scrollableState.position.pixels, greaterThan(0));

      await tester.ensureVisible(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete').hitTestable(), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(tapped, ['Delete']);
      expect(find.byType(ServerActionsSheet), findsNothing);
    });

    testWidgets('keeps the last action reachable at a large text scale', (
      tester,
    ) async {
      await _pumpHost(tester, size: const Size(320, 480), textScale: 2);
      final tapped = <String>[];
      await _openSheet(tester, tapped);

      final scrollableState = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );
      expect(scrollableState.position.maxScrollExtent, greaterThan(0));

      await tester.ensureVisible(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete').hitTestable(), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(tapped, ['Delete']);
    });

    testWidgets('wraps its content when all actions fit on a tall screen', (
      tester,
    ) async {
      await _pumpHost(tester);
      final tapped = <String>[];
      await _openSheet(tester, tapped);

      final sheetHeight = tester.getSize(find.byType(ServerActionsSheet)).height;
      expect(sheetHeight, lessThan(800 * 0.85));

      final scrollableState = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );
      expect(scrollableState.position.maxScrollExtent, 0);

      for (final label in _labels) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('web-01'), findsOneWidget);
      expect(find.text('10.0.0.1'), findsOneWidget);

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(tapped, ['Connect']);
      expect(find.byType(ServerActionsSheet), findsNothing);
    });
  });
}
