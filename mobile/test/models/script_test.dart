import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/script.dart';

void main() {
  group('parseOsFilter (parity with web osUtils.parseOsFilter)', () {
    test('accepts arrays, JSON strings and null', () {
      expect(parseOsFilter(['Ubuntu', 'Debian']), ['Ubuntu', 'Debian']);
      expect(parseOsFilter('["Ubuntu"]'), ['Ubuntu']);
      expect(parseOsFilter(null), isEmpty);
      expect(parseOsFilter(''), isEmpty);
      expect(parseOsFilter('not json'), isEmpty);
    });
  });

  group('normalizeOsName (parity with web osUtils.normalizeOsName)', () {
    test('maps monitoring names to dialog options', () {
      expect(normalizeOsName('Ubuntu 24.04 LTS'), 'Ubuntu');
      expect(normalizeOsName('debian 12'), 'Debian');
      expect(normalizeOsName('Microsoft Windows Server 2022'), 'Windows');
      expect(normalizeOsName(' Rocky Linux 9'), 'Rocky Linux');
      expect(normalizeOsName('Proxmox VE 8'), 'Proxmox VE');
      expect(normalizeOsName('SomeUnknownDistro'), 'SomeUnknownDistro');
      expect(normalizeOsName(null), isNull);
    });
  });

  group('matchesOsFilter (parity with web osUtils.matchesOsFilter)', () {
    test('empty filter matches everything', () {
      expect(matchesOsFilter([], 'Ubuntu', isPveEntry: false), isTrue);
      expect(matchesOsFilter([], null, isPveEntry: true), isTrue);
    });

    test('filters by normalized OS name', () {
      expect(matchesOsFilter(['Ubuntu'], 'Ubuntu', isPveEntry: false), isTrue);
      expect(matchesOsFilter(['Ubuntu'], 'Debian', isPveEntry: false), isFalse);
      expect(matchesOsFilter(['Windows'], null, isPveEntry: false), isFalse);
    });

    test('PVE entries only match Proxmox VE filter', () {
      expect(matchesOsFilter(['Proxmox VE'], null, isPveEntry: true), isTrue);
      expect(matchesOsFilter(['Ubuntu'], null, isPveEntry: true), isFalse);
      expect(matchesOsFilter(['Proxmox VE'], null, isPveEntry: false), isFalse);
    });
  });

  group('Script model', () {
    test('fromJson parses all fields', () {
      final script = Script.fromJson({
        'id': 7,
        'name': 'Deploy Stack',
        'description': 'Installs the stack',
        'osFilter': '["Ubuntu","Debian"]',
        'organizationId': 3,
        'sortOrder': 2,
      });
      expect(script.id, 7);
      expect(script.name, 'Deploy Stack');
      expect(script.osFilter, ['Ubuntu', 'Debian']);
      expect(script.organizationId, 3);
      expect(script.sourceId, isNull);
      expect(script.isSource, isFalse);
      expect(script.isWindows, isFalse);
      expect(script.osBadges, ['Ubuntu', 'Debian']);
    });

    test('detects Windows target like the server ScriptLayer', () {
      final windows = Script.fromJson({'id': 1, 'name': 'x', 'osFilter': ['Windows']});
      expect(windows.isWindows, isTrue);

      final linux = Script.fromJson({'id': 2, 'name': 'y', 'osFilter': []});
      expect(linux.isWindows, isFalse);
    });

    test('sourceId marks read-only scripts', () {
      final source = Script.fromJson({'id': 4, 'name': 'synced', 'sourceId': 11});
      expect(source.isSource, isTrue);
    });

    test('matchesSearch matches name and description case-insensitively', () {
      final script = Script.fromJson({'id': 1, 'name': 'Deploy Stack', 'description': 'Web server setup'});
      expect(script.matchesSearch('deploy'), isTrue);
      expect(script.matchesSearch('web server'), isTrue);
      expect(script.matchesSearch('apache'), isFalse);
    });
  });
}
