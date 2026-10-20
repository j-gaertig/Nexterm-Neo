import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/app_icons.dart';
import '../../../utils/script_protocol.dart';
import 'script_sheet_result.dart';

/// CSV table, mirroring the web `TableDialog`: first data entry holds the
/// comma-separated headers, the rest are CSV rows. Copy as text / CSV, close
/// sends `input_response` with `value: "closed"`.
Future<ScriptSheetResult?> showScriptTableSheet(BuildContext context, ScriptTableEvent event) {
  return showModalBottomSheet<ScriptSheetResult>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => ScriptTableSheet(event: event),
  );
}

class _ParsedTable {
  final List<String> headers;
  final List<List<String>> rows;

  const _ParsedTable({required this.headers, required this.rows});

  factory _ParsedTable.from(List<String> data) {
    if (data.isEmpty) return const _ParsedTable(headers: [], rows: []);
    final headers = data[0].split(',').map((h) => h.trim()).toList();
    final rows = <List<String>>[];
    for (var i = 1; i < data.length; i++) {
      final rowData = data[i].split(',').map((cell) => cell.trim()).toList();
      while (rowData.length < headers.length) {
        rowData.add('');
      }
      if (rowData.isNotEmpty) rows.add(rowData.sublist(0, headers.length));
    }
    return _ParsedTable(headers: headers, rows: rows);
  }
}

class ScriptTableSheet extends StatelessWidget {
  final ScriptTableEvent event;

  const ScriptTableSheet({super.key, required this.event});

  _ParsedTable get _table => _ParsedTable.from(event.data);

  void _copy(BuildContext context, String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$label copied to clipboard'),
        behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final table = _table;
    final hasData = table.headers.isNotEmpty && table.rows.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(
          margin: const EdgeInsets.only(top: 12, bottom: 4), width: 36, height: 4,
          decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
              child: Icon(AppIcons.viewList, color: cs.onPrimaryContainer, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(event.title, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis)),
          ]),
        ),
        const SizedBox(height: 10),
        Flexible(
          child: hasData
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: DataTable(
                    columnSpacing: 24,
                    headingRowHeight: 40,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 44,
                    columns: [
                      for (final header in table.headers)
                        DataColumn(label: Text(header, style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w700, color: cs.outline))),
                    ],
                    rows: [
                      for (final row in table.rows)
                        DataRow(cells: [
                          for (var i = 0; i < table.headers.length; i++)
                            DataCell(Text(
                              i < row.length ? row[i] : '',
                              style: TextStyle(fontSize: 13, color: cs.onSurface),
                            )),
                        ]),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('No table data available', style: TextStyle(fontSize: 13, color: cs.outline)),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Row(children: [
            if (hasData) ...[
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _copy(context, _tableAsText(table), 'Table data (formatted text)'),
                icon: const Icon(AppIcons.contentCopy, size: 16),
                label: const Text('Copy as Text', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  side: BorderSide(color: cs.outlineVariant),
                ),
              )),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _copy(context, _tableAsCsv(table), 'Table data (CSV)'),
                icon: const Icon(AppIcons.fileDocumentOutline, size: 16),
                label: const Text('Copy as CSV', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  side: BorderSide(color: cs.outlineVariant),
                ),
              )),
              const SizedBox(width: 8),
            ],
            Expanded(child: FilledButton(
              onPressed: () => Navigator.pop(context, const ScriptClosedResult()),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              child: const Text('Close'),
            )),
          ]),
        ),
      ]),
    );
  }

  String _tableAsCsv(_ParsedTable table) => [
        table.headers.join(','),
        ...table.rows.map((row) => row.join(',')),
      ].join('\n');

  String _tableAsText(_ParsedTable table) {
    final maxWidths = [
      for (var i = 0; i < table.headers.length; i++)
        [
          table.headers[i].length,
          ...table.rows.map((row) => (i < row.length ? row[i] : '').length),
        ].reduce((a, b) => a > b ? a : b),
    ];
    String createRow(List<String> data) {
      final cells = [
        for (var i = 0; i < table.headers.length; i++)
          (i < data.length ? data[i] : '').padRight(maxWidths[i]),
      ];
      return '| ${cells.join(' | ')} |';
    }

    final separator =
        '|${maxWidths.map((w) => '-' * (w + 2)).join('|')}|';
    return [
      createRow(table.headers),
      separator,
      ...table.rows.map(createRow),
    ].join('\n');
  }
}
