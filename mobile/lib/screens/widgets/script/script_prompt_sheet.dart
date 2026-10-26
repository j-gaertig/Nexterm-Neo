import 'package:flutter/material.dart';

import '../../../utils/app_icons.dart';
import '../../../utils/script_protocol.dart';
import 'script_sheet_result.dart';
import 'script_sheet_shell.dart';

/// Input / password / confirm / select prompt, mirroring the web
/// `InputDialog`. Submitting sends `input_response`; stopping the script sends
/// `input_cancelled` (server-side Ctrl-C). System back is intercepted too, so a
/// script can never be left waiting because the sheet was dismissed silently.
Future<ScriptSheetResult?> showScriptPromptSheet(
  BuildContext context,
  ScriptPromptEvent prompt,
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
  bool _obscurePassword = true;
  bool _stopping = false;

  ScriptPromptKind get _kind => widget.prompt.kind;
  bool get _isPassword => _kind == ScriptPromptKind.password;
  bool get _hasValueField => _kind == ScriptPromptKind.input || _isPassword;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _hasValueField ? widget.prompt.defaultValue : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String value) {
    if (_stopping) return;
    Navigator.pop(context, ScriptInputResult(value));
  }

  Future<void> _stopFromBack() async {
    if (_stopping) return;
    _stopping = true;
    final stop = await confirmStopScript(context);
    if (!mounted) return;
    _stopping = false;
    if (stop) {
      Navigator.pop(context, const ScriptCancelledResult());
    }
  }

  Future<void> _stopFromButton() => _stopFromBack();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final prompt = widget.prompt;
    final title = switch (_kind) {
      ScriptPromptKind.password => 'Password required',
      ScriptPromptKind.select => 'Choose an option',
      ScriptPromptKind.confirm => 'Confirm action',
      ScriptPromptKind.input => 'Input required',
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stopFromBack();
      },
      child: ScriptSheetShell(
        title: title,
        bodyIsScrollable: true,
        footer: _footer(cs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              prompt.prompt.isEmpty
                  ? 'The script is waiting for input.'
                  : prompt.prompt,
              style: TextStyle(fontSize: 14, height: 1.35, color: cs.onSurface),
            ),
            const SizedBox(height: 16),
            switch (_kind) {
              ScriptPromptKind.select => _selectBody(cs),
              ScriptPromptKind.confirm => _confirmBody(cs),
              ScriptPromptKind.input ||
              ScriptPromptKind.password => _valueField(cs),
            },
          ],
        ),
      ),
    );
  }

  Widget _valueField(ColorScheme cs) => TextField(
    controller: _controller,
    focusNode: _focusNode,
    autofocus: true,
    obscureText: _isPassword && _obscurePassword,
    autocorrect: false,
    enableSuggestions: false,
    onChanged: (_) => setState(() {}),
    onSubmitted: _canSubmit ? (_) => _submit(_controller.text) : null,
    decoration: InputDecoration(
      hintText: _isPassword
          ? 'Enter password...'
          : (widget.prompt.defaultValue.isEmpty
                ? 'Enter value...'
                : widget.prompt.defaultValue),
      suffixIcon: _isPassword
          ? IconButton(
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              icon: Icon(
                _obscurePassword ? AppIcons.eyeOutline : AppIcons.eyeOffOutline,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            )
          : null,
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.primary, width: 1.5),
      ),
    ),
  );

  Widget _selectBody(ColorScheme cs) {
    final options = widget.prompt.options;
    if (options.isEmpty) {
      return Text(
        'No options were provided by the script.',
        style: TextStyle(fontSize: 13, color: cs.outline),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          OutlinedButton(
            onPressed: _stopping ? null : () => _submit(options[i]),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
              alignment: Alignment.centerLeft,
              side: BorderSide(color: cs.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Container(
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.outline,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    options[i],
                    style: const TextStyle(fontSize: 14, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          if (i != options.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _confirmBody(ColorScheme cs) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      'Choose Yes to continue or No to answer negatively. Both answers keep the script running.',
      style: TextStyle(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
    ),
  );

  bool get _canSubmit => _isPassword
      ? _controller.text.isNotEmpty
      : _controller.text.trim().isNotEmpty;

  Widget _footer(ColorScheme cs) {
    final stopButton = TextButton(
      onPressed: _stopping ? null : _stopFromButton,
      style: TextButton.styleFrom(
        foregroundColor: cs.error,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: const Text('Stop script'),
    );

    if (_kind == ScriptPromptKind.select) {
      return stopButton;
    }

    if (_kind == ScriptPromptKind.confirm) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScriptSheetActions(
            primary: scriptSheetPrimaryButton(
              label: 'Yes',
              onPressed: _stopping ? null : () => _submit('Yes'),
            ),
            secondary: [
              ScriptSheetSecondaryButton(
                label: 'No',
                onPressed: _stopping ? null : () => _submit('No'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          stopButton,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        scriptSheetPrimaryButton(
          label: 'Submit',
          onPressed: _canSubmit && !_stopping
              ? () => _submit(_controller.text)
              : null,
        ),
        const SizedBox(height: 4),
        stopButton,
      ],
    );
  }
}
