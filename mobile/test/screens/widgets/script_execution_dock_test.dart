import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/screens/renderers/script_execution_controller.dart';
import 'package:nexterm/screens/widgets/script/script_execution_dock.dart';
import 'package:nexterm/utils/script_protocol.dart';

Future<void> _pumpDock(
  WidgetTester tester, {
  required ScriptExecutionController controller,
  VoidCallback? onStop,
  VoidCallback? onClose,
  VoidCallback? onReconnect,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ScriptExecutionDock(
            controller: controller,
            serverName: 'web-01',
            onStop: onStop ?? () {},
            onClose: onClose ?? () {},
            onReconnect: onReconnect ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _expand(WidgetTester tester) async {
  await tester.tap(find.text('Details'));
  // The dock animates its height; stopping at a fixed duration also avoids
  // waiting for the indeterminate progress indicator while a script runs.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScriptExecutionDock', () {
    testWidgets('shows the script name and connecting state collapsed', (
      tester,
    ) async {
      final controller = ScriptExecutionController(scriptName: 'Deploy app');
      addTearDown(controller.dispose);

      await _pumpDock(tester, controller: controller);

      expect(find.text('Deploy app'), findsOneWidget);
      expect(find.text('Connecting to script…'), findsOneWidget);
      expect(find.text('Steps'), findsNothing);
    });

    testWidgets('expands when the whole header is tapped', (tester) async {
      final controller = ScriptExecutionController(scriptName: 'Deploy app');
      addTearDown(controller.dispose);
      controller.handleEvent(
        const ScriptStepEvent(number: 1, description: 'Upload files'),
      );

      await _pumpDock(tester, controller: controller);
      await tester.tap(find.text('Deploy app'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Steps'), findsOneWidget);
      expect(find.text('Less'), findsOneWidget);
    });

    testWidgets('expands to show steps, progress and notices', (tester) async {
      final controller = ScriptExecutionController(scriptName: 'Deploy app');
      addTearDown(controller.dispose);
      controller.handleEvent(
        const ScriptStepEvent(number: 1, description: 'Upload files'),
      );
      controller.handleEvent(
        const ScriptStepEvent(number: 2, description: 'Restart service'),
      );
      controller.handleEvent(
        const ScriptProgressEvent(percentage: 50, message: 'Halfway'),
      );
      controller.handleEvent(
        const ScriptNoticeEvent(
          kind: ScriptNoticeKind.warning,
          message: 'Disk almost full',
        ),
      );

      await _pumpDock(tester, controller: controller);
      await _expand(tester);

      expect(find.text('Upload files'), findsOneWidget);
      expect(find.text('Restart service'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('Halfway · Step 2 of 2'), findsOneWidget);
      expect(find.text('Notices'), findsOneWidget);
      expect(find.text('Disk almost full'), findsOneWidget);
    });

    testWidgets('shows the newest notice in the collapsed state', (
      tester,
    ) async {
      final controller = ScriptExecutionController(scriptName: 'Deploy');
      addTearDown(controller.dispose);
      controller.handleEvent(
        const ScriptNoticeEvent(
          kind: ScriptNoticeKind.info,
          message: 'Old notice',
        ),
      );
      controller.handleEvent(
        const ScriptNoticeEvent(
          kind: ScriptNoticeKind.success,
          message: 'New notice',
        ),
      );

      await _pumpDock(tester, controller: controller);

      expect(find.text('New notice'), findsOneWidget);
      expect(find.text('Old notice'), findsNothing);
    });

    testWidgets('calls onStop for a running script', (tester) async {
      final controller = ScriptExecutionController(scriptName: 'Deploy');
      addTearDown(controller.dispose);
      controller.markConnected();
      var stopped = 0;

      await _pumpDock(tester, controller: controller, onStop: () => stopped++);
      await _expand(tester);

      await tester.tap(find.text('Stop script'));
      await tester.pump();

      expect(stopped, 1);
    });

    testWidgets('offers reconnect when the connection was lost', (
      tester,
    ) async {
      final controller = ScriptExecutionController(scriptName: 'Deploy');
      addTearDown(controller.dispose);
      controller.markDisconnected(message: 'Network lost');
      var reconnects = 0;

      await _pumpDock(
        tester,
        controller: controller,
        onReconnect: () => reconnects++,
      );
      await _expand(tester);

      expect(find.text('Network lost'), findsWidgets);
      await tester.tap(find.text('Reconnect'));
      await tester.pump();

      expect(reconnects, 1);
    });

    testWidgets('shows Close instead of Stop after completion', (tester) async {
      final controller = ScriptExecutionController(scriptName: 'Deploy');
      addTearDown(controller.dispose);
      controller.handleEvent(
        const ScriptStepEvent(number: 1, description: 'Work'),
      );
      controller.handleEvent(const ScriptEndEvent(exitCode: 0, success: true));
      var closed = 0;

      await _pumpDock(tester, controller: controller, onClose: () => closed++);
      await _expand(tester);

      expect(find.text('Stop script'), findsNothing);
      expect(find.text('Completed successfully · Step 1 of 1'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pump();

      expect(closed, 1);
    });

    testWidgets('uses a static progress bar after the script ends', (
      tester,
    ) async {
      final controller = ScriptExecutionController(scriptName: 'Deploy');
      addTearDown(controller.dispose);
      controller.markConnected();
      controller.handleEvent(const ScriptEndEvent(exitCode: 0, success: true));

      await _pumpDock(tester, controller: controller);

      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.value, 1.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders user-cancelled scripts as stopped, not failed', (
      tester,
    ) async {
      final controller = ScriptExecutionController(scriptName: 'Deploy');
      addTearDown(controller.dispose);
      controller.markConnected();
      controller.markCancelling();
      controller.handleEvent(
        const ScriptEndEvent(exitCode: 130, success: false),
      );

      await _pumpDock(tester, controller: controller);
      await _expand(tester);

      expect(find.text('Stopped'), findsOneWidget);
      expect(find.textContaining('exited with code'), findsNothing);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('reveals the active step when details open', (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ScriptExecutionController(scriptName: 'Deploy');
      addTearDown(controller.dispose);
      controller.markConnected();
      for (var i = 1; i <= 9; i++) {
        controller.handleEvent(
          ScriptStepEvent(number: i, description: 'Step number $i'),
        );
      }

      await _pumpDock(tester, controller: controller);
      await _expand(tester);

      expect(find.text('Step number 9').hitTestable(), findsOneWidget);
    });

    testWidgets('can close the session while connecting', (tester) async {
      final controller = ScriptExecutionController(scriptName: 'Deploy');
      addTearDown(controller.dispose);
      var closed = 0;

      await _pumpDock(tester, controller: controller, onClose: () => closed++);
      await _expand(tester);

      await tester.tap(find.text('Close session'));
      await tester.pump();

      expect(closed, 1);
    });

    testWidgets('offers reconnect and close when disconnected', (tester) async {
      final controller = ScriptExecutionController(scriptName: 'Deploy');
      addTearDown(controller.dispose);
      controller.markDisconnected(message: 'Network lost');
      var closed = 0;

      await _pumpDock(tester, controller: controller, onClose: () => closed++);
      await _expand(tester);

      expect(find.text('Reconnect'), findsOneWidget);
      await tester.tap(find.text('Close session'));
      await tester.pump();

      expect(closed, 1);
    });

    testWidgets('adapts to large text and a narrow screen', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ScriptExecutionController(scriptName: 'Deploy');
      addTearDown(controller.dispose);
      controller.markConnected();
      controller.handleEvent(
        const ScriptStepEvent(number: 1, description: 'A long step name'),
      );
      controller.handleEvent(
        const ScriptNoticeEvent(
          kind: ScriptNoticeKind.info,
          message: 'A fairly long informational notice',
        ),
      );

      await _pumpDock(tester, controller: controller, textScale: 1.6);
      await _expand(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('A long step name'), findsOneWidget);
    });
  });
}
