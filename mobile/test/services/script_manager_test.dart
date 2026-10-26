import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/monitoring.dart';
import 'package:nexterm/models/script.dart';
import 'package:nexterm/models/server.dart';
import 'package:nexterm/services/script_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Script _script({
  required int id,
  required String name,
  int? organizationId,
  int? sourceId,
  List<String> osFilter = const [],
  int sortOrder = 0,
  String? description,
}) => Script(
  id: id,
  name: name,
  description: description,
  osFilter: osFilter,
  organizationId: organizationId,
  sourceId: sourceId,
  sortOrder: sortOrder,
);

Server _server({int id = 1, String? icon}) =>
    Server(id: id, name: 'web-01', ip: '10.0.0.1', icon: icon, identities: [1]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('filterScriptsForServer', () {
    final scripts = [
      _script(
        id: 1,
        name: 'Personal Ubuntu',
        osFilter: ['Ubuntu'],
        sortOrder: 2,
      ),
      _script(
        id: 2,
        name: 'Personal Windows',
        osFilter: ['Windows'],
        sortOrder: 1,
      ),
      _script(
        id: 3,
        name: 'Org Deploy',
        organizationId: 7,
        description: 'Deploy the app',
        sortOrder: 1,
      ),
      _script(id: 4, name: 'Other Org', organizationId: 8),
      _script(id: 5, name: 'Source universal', sourceId: 99, sortOrder: 3),
      _script(id: 6, name: '???', description: 'What happened?'),
    ];

    test('includes personal, matching organization and source scripts', () {
      final result = filterScriptsForServer(
        scripts: scripts,
        sourceScripts: [
          _script(
            id: 7,
            name: 'Source Ubuntu',
            sourceId: 100,
            osFilter: ['Ubuntu'],
          ),
        ],
        organizationId: 7,
        serverOsName: 'Ubuntu 24.04 LTS',
      );

      expect(result.map((script) => script.id), [7, 3, 1, 5]);
    });

    test('hides scripts from other organizations and secret scripts', () {
      final result = filterScriptsForServer(
        scripts: scripts,
        sourceScripts: const [],
        organizationId: 7,
        serverOsName: null,
      );

      expect(result.map((script) => script.id), isNot(contains(4)));
      expect(result.map((script) => script.id), isNot(contains(6)));
    });

    test('applies OS compatibility unless explicitly disabled', () {
      final compatible = filterScriptsForServer(
        scripts: scripts,
        sourceScripts: const [],
        organizationId: 7,
        serverOsName: 'Windows Server 2022',
      );
      expect(compatible.map((script) => script.id), [3, 2, 5]);

      final all = filterScriptsForServer(
        scripts: scripts,
        sourceScripts: const [],
        organizationId: 7,
        serverOsName: 'Windows Server 2022',
        includeIncompatible: true,
      );
      expect(all.map((script) => script.id), containsAll([1, 2, 3, 5]));
      expect(all.map((script) => script.id), isNot(contains(4)));
    });

    test('shows every OS when the server OS is unknown', () {
      final result = filterScriptsForServer(
        scripts: scripts,
        sourceScripts: const [],
        organizationId: 7,
        serverOsName: null,
      );

      expect(result.map((script) => script.id), containsAll([1, 2, 3, 5]));
    });

    test('searches name and description case-insensitively', () {
      final byName = filterScriptsForServer(
        scripts: scripts,
        sourceScripts: const [],
        organizationId: 7,
        serverOsName: null,
        query: 'WINDOWS',
      );
      expect(byName.single.id, 2);

      final byDescription = filterScriptsForServer(
        scripts: scripts,
        sourceScripts: const [],
        organizationId: 7,
        serverOsName: null,
        query: 'deploy the',
      );
      expect(byDescription.single.id, 3);
    });

    test('deduplicates by id and sorts by sort order then name', () {
      final duplicate = _script(
        id: 3,
        name: 'Duplicate org',
        organizationId: 7,
        sortOrder: 0,
      );
      final result = filterScriptsForServer(
        scripts: [duplicate, ...scripts],
        sourceScripts: const [],
        organizationId: 7,
        serverOsName: null,
      );

      expect(result.where((script) => script.id == 3), hasLength(1));
      expect(result.first.id, 3);
      expect(result.map((script) => script.id).toList(), [3, 2, 1, 5]);
    });
  });

  group('ScriptManager OS detection', () {
    test('prefers monitoring over the icon fallback', () async {
      var calls = 0;
      final manager = ScriptManager(
        monitoringFetcher: (token, id) async {
          calls++;
          return M({
            'latest': {
              'osInfo': {'name': 'Ubuntu 24.04 LTS'},
            },
          });
        },
      );
      addTearDown(manager.dispose);

      final name = await manager.serverOsName(
        _server(icon: 'windows'),
        'token',
      );

      expect(name, 'Ubuntu');
      expect(calls, 1);

      final cached = await manager.serverOsName(
        _server(icon: 'windows'),
        'token',
      );
      expect(cached, 'Ubuntu');
      expect(calls, 1);
    });

    test('falls back to the server icon when monitoring fails', () async {
      final manager = ScriptManager(
        monitoringFetcher: (token, id) async => throw Exception('offline'),
      );
      addTearDown(manager.dispose);

      expect(
        await manager.serverOsName(_server(icon: 'windows-server'), 'token'),
        'Windows',
      );
      expect(
        await manager.serverOsName(_server(id: 2, icon: 'ubuntu'), 'token'),
        'Ubuntu',
      );
    });

    test('returns null when neither source identifies the OS', () async {
      final manager = ScriptManager(
        monitoringFetcher: (token, id) async => M({}),
      );
      addTearDown(manager.dispose);

      expect(
        await manager.serverOsName(_server(icon: 'server'), 'token'),
        isNull,
      );
    });

    test('refresh bypasses the cached OS value', () async {
      var calls = 0;
      final manager = ScriptManager(
        monitoringFetcher: (token, id) async {
          calls++;
          return M({
            'latest': {
              'osInfo': {'name': calls == 1 ? 'Ubuntu' : 'Debian'},
            },
          });
        },
      );
      addTearDown(manager.dispose);

      expect(await manager.serverOsName(_server(), 'token'), 'Ubuntu');
      expect(
        await manager.serverOsName(_server(), 'token', refresh: true),
        'Debian',
      );
      expect(calls, 2);
    });
  });

  group('ScriptManager cache and preferences', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'loads both catalogues, caches failures, and supports refresh',
      () async {
        var scriptCalls = 0;
        var sourceCalls = 0;
        final manager = ScriptManager(
          scriptsFetcher: (token) async {
            scriptCalls++;
            return [
              _script(id: 1, name: 'B', sortOrder: 1),
              _script(id: 2, name: 'A', sortOrder: 1),
            ];
          },
          sourceScriptsFetcher: (token) async {
            sourceCalls++;
            return [_script(id: 3, name: 'Source', sourceId: 9)];
          },
        );
        addTearDown(manager.dispose);

        await manager.ensureLoaded('token');
        expect(manager.hasLoaded, isTrue);
        expect(manager.scripts.map((script) => script.name), ['A', 'B']);
        expect(manager.sourceScripts.single.name, 'Source');
        expect(manager.scriptById(3)?.name, 'Source');
        expect(manager.scriptById(999), isNull);

        await manager.ensureLoaded('token');
        expect(scriptCalls, 1);
        expect(sourceCalls, 1);

        await manager.ensureLoaded('token', refresh: true);
        expect(scriptCalls, 2);
        expect(sourceCalls, 2);
      },
    );

    test('source script failures leave the base catalogue usable', () async {
      final manager = ScriptManager(
        scriptsFetcher: (token) async => [_script(id: 1, name: 'Base')],
        sourceScriptsFetcher: (token) async => throw Exception('no sources'),
      );
      addTearDown(manager.dispose);

      await manager.ensureLoaded('token');

      expect(manager.scripts.single.name, 'Base');
      expect(manager.sourceScripts, isEmpty);
      expect(manager.error, isNull);
    });

    test('a base catalogue failure is reported and can be retried', () async {
      var fail = true;
      final manager = ScriptManager(
        scriptsFetcher: (token) async {
          if (fail) throw Exception('network');
          return [_script(id: 1, name: 'Base')];
        },
        sourceScriptsFetcher: (token) async => const [],
      );
      addTearDown(manager.dispose);

      await expectLater(manager.ensureLoaded('token'), throwsException);
      expect(manager.error, contains('network'));
      expect(manager.hasLoaded, isFalse);

      fail = false;
      await manager.ensureLoaded('token');
      expect(manager.hasLoaded, isTrue);
      expect(manager.error, isNull);
    });

    test('favorites and recents persist and are capped', () async {
      SharedPreferences.setMockInitialValues({
        'script_favorites': '[3,1]',
        'script_recent': '[2,2,3]',
      });
      final manager = ScriptManager();
      addTearDown(manager.dispose);

      await manager.loadPreferences();
      expect(manager.favoriteIds, {3, 1});
      expect(manager.recentIds, [2, 3]);

      await manager.toggleFavorite(3);
      await manager.toggleFavorite(5);
      expect(manager.isFavorite(3), isFalse);
      expect(manager.isFavorite(5), isTrue);

      for (var id = 10; id < 16; id++) {
        await manager.recordRecent(id);
      }
      expect(manager.recentIds, [15, 14, 13, 12, 11]);

      final reloaded = ScriptManager();
      addTearDown(reloaded.dispose);
      await reloaded.loadPreferences();
      expect(reloaded.favoriteIds, {1, 5});
      expect(reloaded.recentIds, [15, 14, 13, 12, 11]);
    });

    test('invalid preference data is ignored instead of throwing', () async {
      SharedPreferences.setMockInitialValues({
        'script_favorites': 'not json',
        'script_recent': '{"not":"a list"}',
      });
      final manager = ScriptManager();
      addTearDown(manager.dispose);

      await manager.loadPreferences();

      expect(manager.favoriteIds, isEmpty);
      expect(manager.recentIds, isEmpty);
    });

    test('seedForTesting provides an already fresh catalogue', () async {
      final manager = ScriptManager();
      addTearDown(manager.dispose);

      manager.seedForTesting(
        scripts: [_script(id: 1, name: 'Seeded')],
        sources: [_script(id: 2, name: 'Source', sourceId: 1)],
      );

      expect(manager.hasLoaded, isTrue);
      expect(manager.hasFreshData, isTrue);
      expect(manager.scripts.single.name, 'Seeded');
      expect(manager.sourceScripts.single.name, 'Source');
    });
  });
}
