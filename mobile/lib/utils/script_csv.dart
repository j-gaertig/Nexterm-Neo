/// Minimal CSV support for script table dialogs.
///
/// The server transports each table row as one flat string (see
/// `@NEXTERM:TABLE:`). Cells may contain commas when the script quotes them,
/// so splitting on `,` loses data. This parser handles quoted fields and
/// escaped quotes while remaining deliberately small (no embedded newlines:
/// the wire protocol is line-oriented).
class ScriptTableData {
  final List<String> headers;
  final List<List<String>> rows;

  const ScriptTableData({required this.headers, required this.rows});

  factory ScriptTableData.fromWireData(List<String> data) {
    if (data.isEmpty) return const ScriptTableData(headers: [], rows: []);
    final headers = parseCsvLine(data.first);
    final rows = <List<String>>[];
    for (var i = 1; i < data.length; i++) {
      final row = parseCsvLine(data[i]);
      while (row.length < headers.length) {
        row.add('');
      }
      if (headers.isNotEmpty) {
        rows.add(row.sublist(0, headers.length));
      }
    }
    return ScriptTableData(headers: headers, rows: rows);
  }

  bool get isEmpty => headers.isEmpty || rows.isEmpty;

  String asCsv() => [
    headers.map(encodeCsvField).join(','),
    ...rows.map((row) => row.map(encodeCsvField).join(',')),
  ].join('\n');

  String asText() {
    if (headers.isEmpty) return '';
    final widths = <int>[
      for (var i = 0; i < headers.length; i++)
        [
          headers[i].length,
          ...rows.map((row) => i < row.length ? row[i].length : 0),
        ].reduce((a, b) => a > b ? a : b),
    ];
    String line(List<String> cells) =>
        '| ${[for (var i = 0; i < headers.length; i++) (i < cells.length ? cells[i] : '').padRight(widths[i])].join(' | ')} |';

    return [
      line(headers),
      '|${widths.map((w) => '-' * (w + 2)).join('|')}|',
      ...rows.map(line),
    ].join('\n');
  }
}

/// Parses one CSV line. Supports `"quoted, fields"` and `""` escapes.
List<String> parseCsvLine(String line) {
  final cells = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  var i = 0;
  while (i < line.length) {
    final char = line[i];
    if (inQuotes) {
      if (char == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      buffer.write(char);
      i++;
      continue;
    }

    if (char == '"' && buffer.isEmpty) {
      inQuotes = true;
      i++;
    } else if (char == ',') {
      cells.add(buffer.toString().trim());
      buffer.clear();
      i++;
    } else {
      buffer.write(char);
      i++;
    }
  }
  cells.add(buffer.toString().trim());
  return cells;
}

String encodeCsvField(String value) {
  if (value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
