import '../../../utils/script_protocol.dart';

/// Result of one script sheet interaction. The renderer turns it into the
/// matching wire message:
/// - `ScriptInputResult` → `input_response`
/// - `ScriptCancelledResult` → `input_cancelled` (server sends Ctrl-C)
/// - `ScriptClosedResult` → `input_response` with `value: "closed"`
///   (summary/table/msgbox close, mirrors web `closeDialog`)
sealed class ScriptSheetResult {
  const ScriptSheetResult();
}

class ScriptInputResult extends ScriptSheetResult {
  final String value;
  const ScriptInputResult(this.value);
}

class ScriptCancelledResult extends ScriptSheetResult {
  const ScriptCancelledResult();
}

class ScriptClosedResult extends ScriptSheetResult {
  const ScriptClosedResult();
}

/// A prompt/confirm request shown as a modal bottom sheet.
class ScriptSheetRequest {
  final ScriptPromptEvent? prompt;
  final ScriptSummaryEvent? summary;
  final ScriptTableEvent? table;
  final ScriptMessageBoxEvent? messageBox;

  const ScriptSheetRequest({
    this.prompt,
    this.summary,
    this.table,
    this.messageBox,
  });

  bool get isPrompt => prompt != null;
  bool get isSummary => summary != null;
  bool get isTable => table != null;
  bool get isMessageBox => messageBox != null;
  bool get isInformational =>
      summary != null || table != null || messageBox != null;
}

/// Display-only context attached to a script sheet. The wire protocol carries
/// the prompt data, not the script/server name, so the renderer passes this in
/// separately to make the modal self-explanatory.
class ScriptSheetContext {
  final String? scriptName;
  final String? serverName;
  final String? stepLabel;

  const ScriptSheetContext({this.scriptName, this.serverName, this.stepLabel});

  String get description {
    final parts = <String>[
      if (scriptName != null && scriptName!.isNotEmpty) scriptName!,
      if (serverName != null && serverName!.isNotEmpty) serverName!,
      if (stepLabel != null && stepLabel!.isNotEmpty) stepLabel!,
    ];
    return parts.join(' · ');
  }
}
