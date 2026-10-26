import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/app_icons.dart';
import '../../../utils/script_csv.dart';
import '../../../utils/script_protocol.dart';
import 'script_sheet_result.dart';
import 'script_sheet_shell.dart';

/// CSV table, mirroring the web `TableDialog`. The first data entry holds the
/// CSV headers, the rest are CSV rows. The table scrolls in both directions,
/// keeps the header pinned while scrolling vertically, and copies either
/// CSV or a formatted text representation. Closing sends `input_response` with
/// `value: "closed"`.
Future<ScriptSheetResult?> showScriptTableSheet(
  BuildContext context,
  ScriptTableEvent event, {
  ScriptSheetContext? contextInfo,
}) {
  return showModalBottomSheet<ScriptSheetResult>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ScriptTableSheet(event: event, contextInfo: contextInfo),
  );
}

class ScriptTableSheet extends StatelessWidget {
  final ScriptTableEvent event;
  final ScriptSheetContext? contextInfo;

  const ScriptTableSheet({super.key, required this.event, this.contextInfo});

  ScriptTableData get _table => ScriptTableData.fromWireData(event.data);

  void _close(BuildContext context) {
    Navigator.pop(context, const ScriptClosedResult());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final table = _table;
    final hasData = !table.isEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(context);
      },
      child: ScriptSheetShell(
        title: event.title.isEmpty ? 'Script Table' : event.title,
        icon: AppIcons.viewList,
        contextInfo: contextInfo,
        bodyIsScrollable: false,
        footer: ScriptSheetActions(
          stackOverride: false,
          primary: scriptSheetPrimaryButton(
            label: 'Close',
            icon: AppIcons.check,
            onPressed: () => _close(context),
          ),
          secondary: [
            if (hasData)
              ScriptCopyButton(
                label: 'Copy CSV',
                icon: AppIcons.fileDocumentOutline,
                onCopy: () =>
                    Clipboard.setData(ClipboardData(text: table.asCsv())),
              ),
            if (hasData)
              ScriptCopyButton(
                label: 'Copy text',
                icon: AppIcons.contentCopy,
                onCopy: () =>
                    Clipboard.setData(ClipboardData(text: table.asText())),
              ),
          ],
        ),
        child: hasData
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(AppIcons.viewList, size: 14, color: cs.outline),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${table.rows.length} ${table.rows.length == 1 ? 'row' : 'rows'} · ${table.headers.length} ${table.headers.length == 1 ? 'column' : 'columns'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: cs.outline),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(child: _ScrollableScriptTable(table: table)),
                ],
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

  const _ScrollableScriptTable({required this.table});

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
    return (longest * scaled + 26).clamp(96.0, 220.0);
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
        final height = constraints.maxHeight.isFinite
            ? math.max(0.0, constraints.maxHeight)
            : 360.0;
        return Scrollbar(
          controller: _horizontalController,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(totalWidth, constraints.maxWidth),
              height: height,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    constraints: const BoxConstraints(minHeight: 42),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      border: Border(
                        bottom: BorderSide(color: cs.outlineVariant),
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(10),
                      ),
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < headers.length; i++)
                          SizedBox(
                            width: widths[i],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
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
                  ),
                  Expanded(
                    child: Scrollbar(
                      controller: _verticalController,
                      child: ListView.builder(
                        controller: _verticalController,
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return Container(
                            decoration: BoxDecoration(
                              color: index.isEven
                                  ? Colors.transparent
                                  : cs.surfaceContainerLow.withValues(
                                      alpha: 0.55,
                                    ),
                              border: Border(
                                bottom: BorderSide(
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.55,
                                  ),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                for (var i = 0; i < headers.length; i++)
                                  SizedBox(
                                    width: widths[i],
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 10,
                                      ),
                                      child: Text(
                                        i < row.length ? row[i] : '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          height: 1.25,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
