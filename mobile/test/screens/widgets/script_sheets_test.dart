import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/screens/widgets/script/script_message_sheet.dart';
import 'package:nexterm/screens/widgets/script/script_prompt_sheet.dart';
import 'package:nexterm/screens/widgets/script/script_sheet_result.dart';
import 'package:nexterm/screens/widgets/script/script_summary_sheet.dart';
import 'package:nexterm/screens/widgets/script/script_table_sheet.dart';
import 'package:nexterm/utils/script_protocol.dart';

Future<void> _pumpHost(WidgetTester tester, double textScale) async {
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
        body: Builder(
          builder: (context) {
            hostContext = context;
            return const Center(child: Text('Host'));
          },
        ),
      ),
    ),
  );
}

late BuildContext hostContext;

Future<void> _pumpSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Advance through route animations without waiting for the text cursor's
/// blinking timer, which would make [WidgetTester.pumpAndSettle] time out.
Future<void> _settleUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

ScriptPromptEvent _prompt({
  ScriptPromptKind kind = ScriptPromptKind.input,
  String prompt = 'Please answer',
  String defaultValue = '',
  List<String> options = const [],
}) => ScriptPromptEvent(
  kind: kind,
  variable: 'VALUE',
  prompt: prompt,
  defaultValue: defaultValue,
  options: options,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScriptPromptSheet', () {
    testWidgets('submits entered text', (tester) async {
      await _pumpHost(tester, 1);
      final result = showScriptPromptSheet(hostContext, _prompt());
      await _pumpSheet(tester);

      expect(find.text('Input required'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await _settleUi(tester);

      expect(await result, isA<ScriptInputResult>());
      expect((await result as ScriptInputResult).value, 'hello');
      expect(find.byType(TextField), findsNothing);
    });
    testWidgets('prefills and trims input before enabling submit', (
      tester,
    ) async {
      await _pumpHost(tester, 1);
      showScriptPromptSheet(hostContext, _prompt(defaultValue: 'default'));
      await _pumpSheet(tester);

      expect(find.text('default'), findsWidgets);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit'),
      );
      expect(button.onPressed, isNull);

      await tester.enterText(find.byType(TextField), '  value  ');
      await tester.pump();
      final enabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit'),
      );
      expect(enabled.onPressed, isNotNull);
    });

    testWidgets('reveals and hides passwords', (tester) async {
      await _pumpHost(tester, 1);
      showScriptPromptSheet(
        hostContext,
        _prompt(kind: ScriptPromptKind.password, defaultValue: 'secret'),
      );
      await _pumpSheet(tester);

      expect(find.text('Password required'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );

      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isFalse,
      );

      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
    });

    testWidgets('returns the selected option', (tester) async {
      await _pumpHost(tester, 1);
      final result = showScriptPromptSheet(
        hostContext,
        _prompt(
          kind: ScriptPromptKind.select,
          options: const ['Option A', 'Option B'],
        ),
      );
      await _pumpSheet(tester);

      await tester.tap(find.text('Option B'));
      await _settleUi(tester);

      expect((await result as ScriptInputResult).value, 'Option B');
    });

    testWidgets('returns yes and no for a confirmation prompt', (tester) async {
      await _pumpHost(tester, 1);
      var result = showScriptPromptSheet(
        hostContext,
        _prompt(kind: ScriptPromptKind.confirm),
      );
      await _pumpSheet(tester);

      await tester.tap(find.text('Yes'));
      await _settleUi(tester);
      expect((await result as ScriptInputResult).value, 'Yes');

      result = showScriptPromptSheet(
        hostContext,
        _prompt(kind: ScriptPromptKind.confirm),
      );
      await _pumpSheet(tester);
      await tester.tap(find.text('No'));
      await _settleUi(tester);
      expect((await result as ScriptInputResult).value, 'No');
    });

    testWidgets('system back asks before stopping and can keep running', (
      tester,
    ) async {
      await _pumpHost(tester, 1);
      final result = showScriptPromptSheet(hostContext, _prompt());
      await _pumpSheet(tester);

      await tester.binding.handlePopRoute();
      await _settleUi(tester);
      expect(find.text('Stop script?'), findsOneWidget);
      expect(
        tester
            .getSize(find.widgetWithText(OutlinedButton, 'Keep running'))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.widgetWithText(FilledButton, 'Stop script')).height,
        greaterThanOrEqualTo(48),
      );

      await tester.tap(find.text('Keep running'));
      await _settleUi(tester);
      expect(find.text('Input required'), findsOneWidget);
      expect(find.text('Stop script?'), findsNothing);

      await tester.binding.handlePopRoute();
      await _settleUi(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Stop script'),
        ),
      );
      await _settleUi(tester);

      expect(await result, isA<ScriptCancelledResult>());
      expect(find.text('Input required'), findsNothing);
    });

    testWidgets('stop confirmation fits a small screen at 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpHost(tester, 2);
      showScriptPromptSheet(hostContext, _prompt());
      await _pumpSheet(tester);

      await tester.tap(find.text('Stop script'));
      await _settleUi(tester);

      expect(find.text('Stop script?'), findsOneWidget);
      expect(find.text('Keep running').hitTestable(), findsOneWidget);
      expect(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Stop script'),
            )
            .hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Keep running'));
      await _settleUi(tester);
      expect(find.text('Stop script?'), findsNothing);
    });

    testWidgets('stops from the footer after confirmation', (tester) async {
      await _pumpHost(tester, 1);
      final result = showScriptPromptSheet(hostContext, _prompt());
      await _pumpSheet(tester);

      await tester.tap(find.text('Stop script'));
      await _settleUi(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Stop script'),
        ),
      );
      await _settleUi(tester);

      expect(await result, isA<ScriptCancelledResult>());
    });

    testWidgets('fits a small screen with large text', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpHost(tester, 1.6);

      showScriptPromptSheet(
        hostContext,
        _prompt(
          kind: ScriptPromptKind.select,
          prompt:
              'Choose the deployment target for the production environment.',
          options: const [
            'Production cluster in Frankfurt',
            'Staging cluster in Amsterdam',
            'Development cluster on the local machine',
          ],
        ),
      );
      await _pumpSheet(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Production cluster in Frankfurt'), findsOneWidget);
    });

    testWidgets('fits a small screen with keyboard open at 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await _pumpHost(tester, 2);

      showScriptPromptSheet(
        hostContext,
        _prompt(
          prompt:
              'Enter the database password for the production cluster. This prompt can span several lines.',
        ),
      );
      await _pumpSheet(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Input required'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('ScriptSummarySheet', () {
    testWidgets('renders key/value pairs and closes with a response', (
      tester,
    ) async {
      await _pumpHost(tester, 1);
      final result = showScriptSummarySheet(
        hostContext,
        const ScriptSummaryEvent(
          title: 'Deployment summary',
          data: [
            'Server',
            'web-01',
            'Status',
            'success',
            'URL',
            'https://example.com',
          ],
        ),
      );
      await _pumpSheet(tester);

      expect(find.text('Deployment summary'), findsOneWidget);
      expect(find.text('Server'), findsOneWidget);
      expect(find.text('web-01'), findsOneWidget);
      expect(find.text('https://example.com'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await _settleUi(tester);

      expect(await result, isA<ScriptClosedResult>());
    });

    testWidgets('shows copy feedback inside the modal sheet', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async => null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await _pumpHost(tester, 1);
      showScriptSummarySheet(
        hostContext,
        const ScriptSummaryEvent(title: 'Summary', data: ['Key', 'Value']),
      );
      await _pumpSheet(tester);

      expect(
        tester.getSize(find.widgetWithText(OutlinedButton, 'Copy all')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('Copy all'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Copied'), findsOneWidget);
      expect(find.text('Copy all'), findsNothing);
      // Let the inline feedback timer expire inside the fake async zone.
      await tester.pump(const Duration(milliseconds: 1700));
      expect(find.text('Copy all'), findsOneWidget);
    });

    testWidgets('system back closes with a response', (tester) async {
      await _pumpHost(tester, 1);
      final result = showScriptSummarySheet(
        hostContext,
        const ScriptSummaryEvent(title: 'Summary', data: ['Key', 'Value']),
      );
      await _pumpSheet(tester);

      await tester.binding.handlePopRoute();
      await _settleUi(tester);

      expect(await result, isA<ScriptClosedResult>());
    });

    testWidgets('handles empty and odd-length summary data', (tester) async {
      await _pumpHost(tester, 1);
      var result = showScriptSummarySheet(
        hostContext,
        const ScriptSummaryEvent(title: 'Empty', data: []),
      );
      await _pumpSheet(tester);
      expect(find.text('No summary data available'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await _settleUi(tester);
      expect(await result, isA<ScriptClosedResult>());

      result = showScriptSummarySheet(
        hostContext,
        const ScriptSummaryEvent(
          title: 'Odd summary',
          data: ['Key', 'Value', 'Odd'],
        ),
      );
      await _pumpSheet(tester);
      expect(find.text('Key'), findsOneWidget);
      expect(find.text('Odd'), findsNothing);
    });
  });

  group('ScriptTableSheet', () {
    testWidgets('renders headers and quoted cell values', (tester) async {
      await _pumpHost(tester, 1);
      final result = showScriptTableSheet(
        hostContext,
        const ScriptTableEvent(
          title: 'Services',
          data: ['Name,Status', 'alpha,ok', '"beta, two",failed'],
        ),
      );
      await _pumpSheet(tester);

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta, two'), findsOneWidget);
      expect(find.text('2 rows · 2 columns'), findsNothing);

      final horizontalScrolls = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .where((view) => view.scrollDirection == Axis.horizontal);
      expect(horizontalScrolls, isNotEmpty);
      expect(
        tester.getSize(find.widgetWithText(OutlinedButton, 'Copy text')).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.widgetWithText(FilledButton, 'Close')).height,
        greaterThanOrEqualTo(48),
      );

      await tester.tap(find.text('Close'));
      await _settleUi(tester);
      expect(await result, isA<ScriptClosedResult>());
    });

    testWidgets('shows a draggable scrollbar for wide tables', (tester) async {
      await _pumpHost(tester, 1);
      showScriptTableSheet(
        hostContext,
        const ScriptTableEvent(
          title: 'Wide table',
          data: [
            'Name,Status,Version,Region,Latency,Duration',
            'api-gateway,healthy,2.18.3,eu-central-1,23ms,1.2s',
            'worker-queue,healthy,2.18.3,eu-central-1,18ms,0.8s',
            'billing-service,degraded,2.17.9,eu-west-1,182ms,9.4s',
          ],
        ),
      );
      await _pumpSheet(tester);

      final scrollbar = find.byKey(
        const ValueKey('script-table-horizontal-scrollbar'),
      );
      expect(scrollbar, findsOneWidget);

      final horizontal = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .firstWhere((state) => state.position.axis == Axis.horizontal);
      expect(horizontal.position.maxScrollExtent, greaterThan(0));

      await tester.drag(scrollbar, const Offset(120, 0));
      await tester.pump();

      expect(horizontal.position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows an empty state without data', (tester) async {
      await _pumpHost(tester, 1);
      showScriptTableSheet(
        hostContext,
        const ScriptTableEvent(title: 'Empty table', data: []),
      );
      await _pumpSheet(tester);

      expect(find.text('No table data available'), findsOneWidget);
      expect(find.text('Copy CSV'), findsNothing);
    });

    testWidgets('fits a small screen with many columns and large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpHost(tester, 1.6);

      showScriptTableSheet(
        hostContext,
        const ScriptTableEvent(
          title: 'A table with a long title',
          data: [
            'Name,Status,Owner,Region,Updated',
            'a-very-long-service-name,operational,platform-team,eu-central-1,2026-10-25',
          ],
        ),
      );
      await _pumpSheet(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('operational'), findsOneWidget);
    });

    testWidgets('fits a small screen at 200% text', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpHost(tester, 2);

      showScriptTableSheet(
        hostContext,
        const ScriptTableEvent(
          title: 'A table with a long title',
          data: [
            'Name,Status,Owner,Region,Updated',
            'a-very-long-service-name,operational,platform-team,eu-central-1,2026-10-25',
          ],
        ),
      );
      await _pumpSheet(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('operational'), findsOneWidget);
    });
  });

  group('ScriptMessageSheet', () {
    testWidgets('unescapes newlines and closes with a response', (
      tester,
    ) async {
      await _pumpHost(tester, 1);
      final result = showScriptMessageSheet(
        hostContext,
        const ScriptMessageBoxEvent(
          title: 'Notice',
          message: r'Line one\nLine two',
        ),
      );
      await _pumpSheet(tester);

      expect(find.text('Line one\nLine two'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await _settleUi(tester);

      expect(await result, isA<ScriptClosedResult>());
    });

    testWidgets('programmatic pop still closes a PopScope sheet', (
      tester,
    ) async {
      await _pumpHost(tester, 1);
      final result = showScriptMessageSheet(
        hostContext,
        const ScriptMessageBoxEvent(title: 'Notice', message: 'Hello'),
      );
      await _pumpSheet(tester);

      Navigator.of(hostContext).pop();
      await _settleUi(tester);

      expect(find.text('Notice'), findsNothing);
      expect(await result, isNull);
    });

    testWidgets('handles an empty message and a long title', (tester) async {
      await _pumpHost(tester, 1);
      showScriptMessageSheet(
        hostContext,
        const ScriptMessageBoxEvent(
          title: 'A very long script message title that has to wrap',
          message: '',
        ),
      );
      await _pumpSheet(tester);

      expect(find.text('The script sent an empty message.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
