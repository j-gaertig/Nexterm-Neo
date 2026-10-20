import 'package:flutter/material.dart';

import '../../../utils/app_icons.dart';
import '../../../utils/script_protocol.dart';
import 'script_sheet_result.dart';

/// Input / password / confirm / select prompt, mirroring the web
/// `InputDialog`: non-dismissible, submits `input_response`, cancel sends
/// `input_cancelled` (server-side Ctrl-C). Select submits the option text,
/// confirm submits `Yes` / `No` — exactly the values the transformed script
/// reads via `read -r`.
Future<ScriptSheetResult?> showScriptPromptSheet(BuildContext context, ScriptPromptEvent prompt) {
  return showModalBottomSheet<ScriptSheetResult>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => ScriptPromptSheet(prompt: prompt),
  );
}

class ScriptPromptSheet extends StatefulWidget {
  final ScriptPromptEvent prompt;

  const ScriptPromptSheet({super.key, required this.prompt});

  @override
  State<ScriptPromptSheet> createState() => _ScriptPromptSheetState();
}

class _ScriptPromptSheetState extends State<ScriptPromptSheet> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  ScriptPromptKind get _kind => widget.prompt.kind;
  bool get _isPassword => _kind == ScriptPromptKind.password;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: _kind == ScriptPromptKind.input || _isPassword ? widget.prompt.defaultValue : '');
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String value) => Navigator.pop(context, ScriptInputResult(value));

  void _cancel() => Navigator.pop(context, const ScriptCancelledResult());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
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
                child: Icon(_kind == ScriptPromptKind.password ? AppIcons.lockOutline : AppIcons.codeBraces,
                    color: cs.onPrimaryContainer, size: 18),
              ),
              const SizedBox(width: 12),
              Text('Input Required', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _promptBody(cs)),
          ),
        ]),
      ),
    );
  }

  List<Widget> _promptBody(ColorScheme cs) {
    final description = Text(
      widget.prompt.prompt.isEmpty ? 'The script is waiting for input' : widget.prompt.prompt,
      style: const TextStyle(fontSize: 14),
    );
    switch (_kind) {
      case ScriptPromptKind.select:
        return [description, const SizedBox(height: 14), ..._optionsList(cs)];
      case ScriptPromptKind.confirm:
        return [description, const SizedBox(height: 14), ..._confirmActions(cs)];
      case ScriptPromptKind.input:
      case ScriptPromptKind.password:
        return [description, const SizedBox(height: 14), _valueField(cs), _textActions(cs)];
    }
  }

  List<Widget> _optionsList(ColorScheme cs) {
    final options = widget.prompt.options;
    return [
      Text('Select an option',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.outline)),
      const SizedBox(height: 8),
      for (final option in options) ...[
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _submit(option),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              alignment: Alignment.centerLeft,
              side: BorderSide(color: cs.outlineVariant),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(option, style: const TextStyle(fontSize: 14)),
          ),
        ),
        const SizedBox(height: 6),
      ],
      const SizedBox(height: 4),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _cancel,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: BorderSide(color: cs.outlineVariant),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Cancel', style: TextStyle(fontSize: 14)),
        ),
      ),
    ];
  }

  List<Widget> _confirmActions(ColorScheme cs) => [
        Text('Confirm action',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.outline)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: FilledButton.icon(
            onPressed: () => _submit('Yes'),
            icon: const Icon(AppIcons.check, size: 16),
            label: const Text('Yes'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: () => _submit('No'),
            icon: Icon(AppIcons.close, size: 16, color: cs.onSurface),
            label: Text('No', style: TextStyle(color: cs.onSurface)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: cs.outlineVariant),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(
            onPressed: _cancel,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: cs.outlineVariant),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 13)),
          )),
        ]),
      ];

  Widget _valueField(ColorScheme cs) => TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        obscureText: _isPassword,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => setState(() {}),
        onSubmitted: _canSubmit ? (_) => _submit(_controller.text) : null,
        decoration: InputDecoration(
          hintText: _isPassword ? 'Enter password...' : (widget.prompt.defaultValue.isEmpty ? 'Enter value...' : widget.prompt.defaultValue),
          prefixIcon: Icon(_isPassword ? AppIcons.lockOutline : AppIcons.codeBraces, size: 20),
          filled: true,
          fillColor: cs.surfaceContainerHigh,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary, width: 1.5)),
        ),
      );

  bool get _canSubmit => _isPassword
      ? _controller.text.isNotEmpty
      : _controller.text.trim().isNotEmpty;

  Widget _textActions(ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: _cancel,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: cs.outlineVariant),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Cancel'),
          )),
          const SizedBox(width: 8),
          Expanded(child: FilledButton.icon(
            onPressed: _canSubmit ? () => _submit(_controller.text) : null,
            icon: const Icon(AppIcons.send, size: 16),
            label: const Text('Submit'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
          )),
        ]),
      );
}
