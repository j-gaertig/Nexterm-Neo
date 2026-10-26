import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/script_protocol.dart';
import 'script_sheet_result.dart';
import 'script_sheet_shell.dart';

/// Message box, mirroring the web `MessageBoxDialog` (`\n` unescaping).
/// Closing (button or system back) sends `input_response` with
/// `value: "closed"`.
Future<ScriptSheetResult?> showScriptMessageSheet(
  BuildContext context,
  ScriptMessageBoxEvent event,
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
    builder: (_) => ScriptMessageSheet(event: event),
  );
}

class ScriptMessageSheet extends StatelessWidget {
  final ScriptMessageBoxEvent event;

  const ScriptMessageSheet({super.key, required this.event});

  void _close(BuildContext context) {
    Navigator.pop(context, const ScriptClosedResult());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Server-side messages escape newlines (`\\n`) — undo like the web client.
    final message = event.message.replaceAll(r'\n', '\n');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(context);
      },
      child: ScriptSheetShell(
        title: event.title.isEmpty ? 'Script Message' : event.title,
        footer: ScriptSheetActions(
          primary: scriptSheetPrimaryButton(
            label: 'OK',
            onPressed: () => _close(context),
          ),
          secondary: [
            ScriptCopyButton(
              label: 'Copy message',
              onCopy: () => Clipboard.setData(
                ClipboardData(
                  text:
                      '${event.title}\n${'=' * event.title.length}\n\n$message',
                ),
              ),
            ),
          ],
        ),
        child: SelectableText(
          message.isEmpty ? 'The script sent an empty message.' : message,
          style: TextStyle(fontSize: 14, color: cs.onSurface, height: 1.45),
        ),
      ),
    );
  }
}
