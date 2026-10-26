import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/script_csv.dart';
import '../../../utils/script_protocol.dart';
import 'script_sheet_result.dart';
import 'script_sheet_shell.dart';

/// CSV table, mirroring the web `TableDialog`. The first data entry holds the
/// CSV headers, the rest are CSV rows. The table scrolls horizontally and
/// vertically and copies either CSV or a formatted text representation. On
/// regular screens the header stays pinned while rows scroll; when space is
/// very tight the whole sheet scrolls instead. Closing sends `input_response`
/// with `value: "closed"`.
Future<ScriptSheetResult?> showScriptTableSheet(
  BuildContext context,
  ScriptTableEvent event,
) {
  return showModalBottomSheet<ScriptSheetResult>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ScriptTableSheet(event: event),
  );
}

class ScriptTableSheet extends StatelessWidget {
  final ScriptTableEvent event;

  const ScriptTableSheet({super.key, required this.event});

  ScriptTableData get _table => ScriptTableData.fromWireData(event.data);

  void _close(BuildContext context) {
    Navigator.pop(context, const ScriptClosedResult());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final table = _table;
    final hasData = !table.isEmpty;
    final media = MediaQuery.of(context);
    final available = math.min(
      media.size.height * 0.88,
      media.size.height - media.viewInsets.bottom - 24,
    );
    final embedded =
        available < 420 || MediaQuery.textScalerOf(context).scale(1.0) > 1.75;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(context);
      },
      child: ScriptSheetShell(
        title: event.title.isEmpty ? 'Script Table' : event.title,
        bodyIsScrollable: false,
        wholeSheetScrollable: embedded,
        footer: ScriptSheetActions(
          primary: scriptSheetPrimaryButton(
            label: 'Close',
            onPressed: () => _close(context),
          ),
          secondary: [
            if (hasData)
              ScriptCopyButton(
                label: 'Copy CSV',
                onCopy: () =>
                    Clipboard.setData(ClipboardData(text: table.asCsv())),
              ),
            if (hasData)
              ScriptCopyButton(
                label: 'Copy text',
                onCopy: () =>
                    Clipboard.setData(ClipboardData(text: table.asText())),
              ),
          ],
        ),
        child: hasData
            ? Container(
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: _ScrollableScriptTable(table: table, embedded: embedded),
              )
            : Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'No table data available',
                  style: TextStyle(fontSize: 13, color: cs.outline),
                ),
              ),
      ),
    );
  }
}

class _ScrollableScriptTable extends StatefulWidget {
  final ScriptTableData table;
  final bool embedded;

  const _ScrollableScriptTable({required this.table, required this.embedded});

  @override
  State<_ScrollableScriptTable> createState() => _ScrollableScriptTableState();
}

class _ScrollableScriptTableState extends State<_ScrollableScriptTable> {
  final _verticalController = ScrollController();
  final _horizontalController = ScrollController();

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  double _columnWidth(int index) {
    final header = widget.table.headers[index];
    var longest = header.length;
    for (final row in widget.table.rows) {
      if (index < row.length && row[index].length > longest) {
        longest = row[index].length;
      }
    }
    final scaled = 7.6 * MediaQuery.textScalerOf(context).scale(1.0);
    return (longest * scaled + 30).clamp(120.0, 260.0);
  }

  Widget _headerRow(ColorScheme cs, List<String> headers, List<double> widths) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < headers.length; i++)
            SizedBox(
              width: widths[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    headers[i],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dataRow(
    ColorScheme cs,
    List<String> headers,
    List<String> row,
    List<double> widths,
    int index,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: index.isEven
            ? Colors.transparent
            : cs.surfaceContainerLow.withValues(alpha: 0.55),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < headers.length; i++)
            SizedBox(
              width: widths[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  i < row.length ? row[i] : '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, height: 1.25),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _horizontalTable({
    required Widget child,
    required double width,
    required bool showThumb,
  }) {
    return Scrollbar(
      controller: _horizontalController,
      thumbVisibility: showThumb,
      thickness: 4,
      radius: const Radius.circular(2),
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: width, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final headers = widget.table.headers;
    final rows = widget.table.rows;
    final widths = [for (var i = 0; i < headers.length; i++) _columnWidth(i)];
    final totalWidth = widths.fold<double>(0, (sum, width) => sum + width);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(totalWidth, constraints.maxWidth);
        if (widget.embedded) {
          return _horizontalTable(
            width: width,
            showThumb: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _headerRow(cs, headers, widths),
                for (var i = 0; i < rows.length; i++)
                  _dataRow(cs, headers, rows[i], widths, i),
              ],
            ),
          );
        }

        final height = constraints.maxHeight.isFinite
            ? math.max(0.0, constraints.maxHeight)
            : 360.0;
        return _horizontalTable(
          width: width,
          showThumb: true,
          child: SizedBox(
            height: height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _headerRow(cs, headers, widths),
                Expanded(
                  child: Scrollbar(
                    controller: _verticalController,
                    child: ListView.builder(
                      controller: _verticalController,
                      itemCount: rows.length,
                      itemBuilder: (context, index) =>
                          _dataRow(cs, headers, rows[index], widths, index),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
