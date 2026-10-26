import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/script_csv.dart';

void main() {
  group('parseCsvLine', () {
    test('parses plain fields and trims whitespace', () {
      expect(parseCsvLine(' alpha, beta ,gamma '), ['alpha', 'beta', 'gamma']);
    });

    test('keeps commas inside quoted fields', () {
      expect(parseCsvLine('"alpha, one",beta'), ['alpha, one', 'beta']);
    });

    test('unescapes doubled quotes', () {
      expect(parseCsvLine('"He said ""hello""",plain'), [
        'He said "hello"',
        'plain',
      ]);
    });

    test('handles empty fields and a trailing comma', () {
      expect(parseCsvLine(',,'), ['', '', '']);
      expect(parseCsvLine('a,,c,'), ['a', '', 'c', '']);
    });

    test('handles a quoted empty field', () {
      expect(parseCsvLine('a,"",c'), ['a', '', 'c']);
    });

    test('keeps quotes that are not at the start of a field', () {
      expect(parseCsvLine('a"b,c'), ['a"b', 'c']);
    });
  });

  group('ScriptTableData', () {
    test('uses the first wire row as headers and pads short rows', () {
      final table = ScriptTableData.fromWireData([
        'Name,Status',
        'alpha,ok',
        'beta',
      ]);

      expect(table.headers, ['Name', 'Status']);
      expect(table.rows, [
        ['alpha', 'ok'],
        ['beta', ''],
      ]);
      expect(table.isEmpty, isFalse);
    });

    test('truncates cells beyond the header count', () {
      final table = ScriptTableData.fromWireData(['A,B', '1,2,3']);

      expect(table.rows.single, ['1', '2']);
    });

    test('handles empty wire data and headers without rows', () {
      expect(ScriptTableData.fromWireData([]).isEmpty, isTrue);
      expect(ScriptTableData.fromWireData(['A,B']).isEmpty, isTrue);
    });

    test('re-encodes CSV with quoting when needed', () {
      final table = ScriptTableData.fromWireData([
        'Name,Note',
        '"alpha, one","He said ""hi"""',
      ]);

      expect(table.asCsv(), 'Name,Note\n"alpha, one","He said ""hi"""');
    });

    test('formats a readable text table', () {
      final table = ScriptTableData.fromWireData(['Name,Status', 'alpha,ok']);

      expect(
        table.asText(),
        '| Name  | Status |\n|-------|--------|\n| alpha | ok     |',
      );
    });
  });

  group('encodeCsvField', () {
    test('only quotes fields that need it', () {
      expect(encodeCsvField('plain'), 'plain');
      expect(encodeCsvField('a,b'), '"a,b"');
      expect(encodeCsvField('a"b'), '"a""b"');
      expect(encodeCsvField('a\nb'), '"a\nb"');
      expect(encodeCsvField('a\rb'), '"a\rb"');
    });
  });
}
