import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/managed_identity.dart';
import 'package:nexterm/models/script.dart';
import 'package:nexterm/models/server.dart';
import 'package:nexterm/screens/widgets/script/run_script_sheet.dart';
import 'package:nexterm/services/script_manager.dart';

late BuildContext hostContext;

Server _server({List<int> identities = const [7]}) => Server(
  id: 1,
  name: 'web-01',
  ip: '10.0.0.1',
  identities: identities,
  protocol: 'ssh',
);

Script _script({
  required int id,
  required String name,
  String? description,
  int? organizationId,
  int? sourceId,
  List<String> osFilter = const [],
  int sortOrder = 0,
}) => Script(
  id: id,
  name: name,
  description: description,
  organizationId: organizationId,
  sourceId: sourceId,
  osFilter: osFilter,
  sortOrder: sortOrder,
);

List<Script> _catalogue() => [
  _script(
    id: 1,
    name: 'Ubuntu deploy',
    osFilter: const ['Ubuntu'],
    sortOrder: 1,
  ),
  _script(
    id: 2,
    name: 'Windows tune',
    osFilter: const ['Windows'],
    sortOrder: 2,
  ),
  _script(
    id: 3,
    name: 'Org deploy',
    organizationId: 7,
    description: 'Deploy the application',
    sortOrder: 3,
  ),
];

Script _sourceScript() =>
    _script(id: 4, name: 'Source setup', sourceId: 99, sortOrder: 4);

ScriptManager _seededManager({List<Script>? scripts, List<Script>? sources}) {
  final manager = ScriptManager();
  manager.seedForTesting(
    scripts: scripts ?? _catalogue(),
    sources: sources ?? [_sourceScript()],
  );
  return manager;
}

Future<void> _pumpHost(WidgetTester tester, {double textScale = 1}) async {
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

Future<void> _pumpSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _settleUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<RunScriptSelection?> _open(
  WidgetTester tester, {
  required ScriptManager manager,
  Server? server,
  int? organizationId = 7,
  Future<String?> Function()? osNameLoader,
  Future<List<ManagedIdentity>> Function(String token)? identitiesLoader,
}) {
  final future = showRunScriptSheet(
    hostContext,
    server ?? _server(),
    'token',
    manager: manager,
    organizationId: organizationId,
    osNameLoader: osNameLoader ?? () async => 'Ubuntu 24.04 LTS',
    identitiesLoader: identitiesLoader,
  );
  return future;
}

Finder get _runButton => find.byKey(const ValueKey('run-script-button'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RunScriptSheet', () {
    testWidgets('lists every script in one flat list without extra chrome', (
      tester,
    ) async {
      final manager = _seededManager();
      addTearDown(manager.dispose);
      await _pumpHost(tester);

      _open(tester, manager: manager);
      await _pumpSheet(tester);

      expect(find.text('Run Script'), findsOneWidget);
      expect(find.text('Ubuntu deploy'), findsOneWidget);
      expect(find.text('Windows tune'), findsOneWidget);
      expect(find.text('Org deploy'), findsOneWidget);
      expect(find.text('Source setup'), findsOneWidget);
      expect(find.text('FAVORITES'), findsNothing);
      expect(find.text('RECENTLY USED'), findsNothing);
      expect(find.text('PERSONAL'), findsNothing);
      expect(find.text('Other OS'), findsNothing);
      expect(find.text('Ubuntu'), findsNothing);
      expect(find.text('Select a script to run'), findsNothing);
      expect(find.byTooltip('Compatible only'), findsOneWidget);
    });

    testWidgets('keeps a searched-away selection and submits it by id', (
      tester,
    ) async {
      final manager = _seededManager();
      addTearDown(manager.dispose);
      await _pumpHost(tester);
      final result = _open(tester, manager: manager);
      await _pumpSheet(tester);

      await tester.tap(find.text('Ubuntu deploy'));
      await tester.pump();
      expect(find.text('Select a script to run'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('No scripts match your search'), findsOneWidget);
      expect(tester.widget<FilledButton>(_runButton).onPressed, isNotNull);

      await tester.tap(_runButton);
      await _settleUi(tester);

      final selection = await result;
      expect(selection, isNotNull);
      expect(selection!.scriptId, 1);
      expect(selection.scriptName, 'Ubuntu deploy');
      expect(selection.identityId, 7);
    });

    testWidgets('compatibility filter is an opt-in square toggle', (
      tester,
    ) async {
      final manager = _seededManager();
      addTearDown(manager.dispose);
      await _pumpHost(tester);

      _open(tester, manager: manager);
      await _pumpSheet(tester);
      expect(find.text('Windows tune'), findsOneWidget);

      await tester.tap(find.byTooltip('Compatible only'));
      await tester.pump();

      expect(find.text('Windows tune'), findsNothing);
      expect(find.text('Ubuntu deploy'), findsOneWidget);
      expect(find.text('Org deploy'), findsOneWidget);
      expect(find.byTooltip('Show all scripts'), findsOneWidget);

      await tester.tap(find.byTooltip('Show all scripts'));
      await tester.pump();

      expect(find.text('Windows tune'), findsOneWidget);
      expect(find.byTooltip('Compatible only'), findsOneWidget);
    });

    testWidgets('shows all scripts when the OS is unknown', (tester) async {
      final manager = _seededManager();
      addTearDown(manager.dispose);
      await _pumpHost(tester);

      _open(tester, manager: manager, osNameLoader: () async => null);
      await _pumpSheet(tester);

      expect(find.text('Windows tune'), findsOneWidget);
      expect(find.byTooltip('Operating system unknown'), findsOneWidget);
      expect(find.text('OS unknown'), findsNothing);
      expect(find.text('All operating systems'), findsNothing);

      await tester.tap(find.byTooltip('Operating system unknown'));
      await tester.pump();
      expect(find.text('Windows tune'), findsOneWidget);
    });

    testWidgets('shows the execution-only empty state when nothing matches', (
      tester,
    ) async {
      final manager = _seededManager(
        scripts: [_script(id: 9, name: 'Someone else', organizationId: 8)],
        sources: const [],
      );
      addTearDown(manager.dispose);
      await _pumpHost(tester);

      _open(tester, manager: manager);
      await _pumpSheet(tester);

      expect(find.text('No scripts available'), findsOneWidget);
      expect(
        find.text('Create and manage scripts in the web client.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(_runButton).onPressed, isNull);
    });

    testWidgets('loads identities and submits the selected one', (
      tester,
    ) async {
      final manager = _seededManager();
      addTearDown(manager.dispose);
      await _pumpHost(tester);

      final result = _open(
        tester,
        manager: manager,
        server: _server(identities: const [1, 2]),
        identitiesLoader: (token) async => const [
          ManagedIdentity(id: 1, name: 'Deploy admin', username: 'admin'),
          ManagedIdentity(id: 2, name: 'Deploy bot', username: 'deploy'),
        ],
      );
      await _pumpSheet(tester);

      expect(find.byTooltip('Run as Deploy admin'), findsOneWidget);
      expect(find.text('DA'), findsOneWidget);
      expect(find.textContaining('Deploy admin'), findsOneWidget);
      expect(find.text('Run as identity'), findsNothing);

      await tester.tap(find.byTooltip('Run as Deploy admin'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Deploy bot').last);
      await _settleUi(tester);

      expect(find.byTooltip('Run as Deploy bot'), findsOneWidget);
      expect(find.text('DB'), findsOneWidget);

      await tester.tap(find.text('Ubuntu deploy'));
      await tester.pump();
      await tester.tap(_runButton);
      await _settleUi(tester);

      expect((await result)!.identityId, 2);
    });

    testWidgets('reports a load failure and retries successfully', (
      tester,
    ) async {
      var fail = true;
      final manager = ScriptManager(
        scriptsFetcher: (token) async {
          if (fail) throw Exception('network down');
          return [_script(id: 1, name: 'Retry script')];
        },
        sourceScriptsFetcher: (token) async => const [],
      );
      addTearDown(manager.dispose);
      await _pumpHost(tester);

      _open(tester, manager: manager);
      await _pumpSheet(tester);
      expect(find.text('Failed to load scripts'), findsOneWidget);
      expect(find.textContaining('network down'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Retry'));
      await _pumpSheet(tester);

      expect(find.text('Failed to load scripts'), findsNothing);
      expect(find.text('Retry script'), findsOneWidget);
    });

    testWidgets('fits a narrow screen with large text', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final manager = _seededManager();
      addTearDown(manager.dispose);
      await _pumpHost(tester, textScale: 1.6);

      _open(tester, manager: manager);
      await _pumpSheet(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Run Script'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Select a script to run'), findsNothing);
      expect(tester.widget<FilledButton>(_runButton).onPressed, isNull);
    });

    testWidgets('stays usable when a small screen keyboard is open', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final manager = _seededManager();
      addTearDown(manager.dispose);
      await _pumpHost(tester, textScale: 1.6);

      _open(tester, manager: manager);
      await _pumpSheet(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Run Script'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Select a script to run'), findsNothing);
      expect(tester.widget<FilledButton>(_runButton).onPressed, isNull);
    });

    testWidgets('keeps identity selection reachable in compact mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final manager = _seededManager();
      addTearDown(manager.dispose);
      await _pumpHost(tester, textScale: 2);

      _open(
        tester,
        manager: manager,
        server: _server(identities: const [1, 2]),
        identitiesLoader: (token) async => [
          ManagedIdentity(id: 1, name: 'Deploy admin', username: 'admin'),
          ManagedIdentity(id: 2, name: 'Deploy bot', username: 'deploy'),
        ],
      );
      await _pumpSheet(tester);

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Run as Deploy admin'), findsOneWidget);
      expect(find.text('DA'), findsOneWidget);

      await tester.tap(find.byTooltip('Run as Deploy admin'));
      await _settleUi(tester);
      await tester.tap(find.text('Deploy bot').last);
      await _settleUi(tester);

      expect(find.byTooltip('Run as Deploy bot'), findsOneWidget);
      expect(find.text('DB'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Ubuntu deploy'),
        80,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Ubuntu deploy'));
      await tester.pump();
      expect(tester.widget<FilledButton>(_runButton).onPressed, isNotNull);
    });
  });
}
