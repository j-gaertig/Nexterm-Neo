import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/app_icons.dart';
import '../../../utils/script_protocol.dart';
import 'script_sheet_result.dart';

/// Message box, mirroring the web `MessageBoxDialog` (`\n` unescaping, copy
/// message). Closing sends `input_response` with `value: "closed"`.
Future<ScriptSheetResult?> showScriptMessageSheet(BuildContext context, ScriptMessageBoxEvent event) {
  return showModalBottomSheet<ScriptSheetResult>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => ScriptMessageSheet(event: event),
  );
}

class ScriptMessageSheet extends StatelessWidget {
  final ScriptMessageBoxEvent event;

  const ScriptMessageSheet({super.key, required this.event});

  void _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Message copied to clipboard'),
        behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // Server-side messages escape newlines (`\\n`) — undo like the web client.
    final message = event.message.replaceAll(r'\n', '\n');

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            child: Icon(AppIcons.alertCircleOutline, color: cs.onPrimaryContainer, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(event.title, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis)),
        ]),
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: SelectableText(message, style: TextStyle(fontSize: 14, color: cs.onSurface, height: 1.4)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () => _copy(context, '${event.title}\n${'=' * event.title.length}\n\n${event.message}'),
            icon: const Icon(AppIcons.contentCopy, size: 16),
            label: const Text('Copy Message'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: cs.outlineVariant),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: FilledButton(
            onPressed: () => Navigator.pop(context, const ScriptClosedResult()),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            child: const Text('OK'),
          )),
        ]),
      ),
    ]);
  }
}
