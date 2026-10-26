import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared visual container for every script dialog. Keeps the header, body,
/// and action area consistent and safe with the keyboard, small screens, and
/// large text.
class ScriptSheetShell extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget footer;
  final bool bodyIsScrollable;
  final bool wholeSheetScrollable;

  const ScriptSheetShell({
    super.key,
    required this.title,
    required this.child,
    required this.footer,
    this.bodyIsScrollable = true,
    this.wholeSheetScrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    final available = math.max(
      0.0,
      math.min(
        media.size.height * 0.88,
        media.size.height - media.viewInsets.bottom - 24,
      ),
    );
    final compact = available < 320;
    final edge = compact ? 12.0 : 20.0;

    final header = <Widget>[
      Center(
        child: Container(
          margin: EdgeInsets.only(top: compact ? 6 : 12, bottom: 4),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: cs.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(edge, compact ? 6 : 12, edge, 0),
        child: Text(
          title,
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      SizedBox(height: compact ? 6 : 10),
    ];

    final footerArea = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: cs.outlineVariant),
        Padding(
          padding: EdgeInsets.fromLTRB(
            edge,
            compact ? 8 : 10,
            edge,
            compact ? 8 : 16,
          ),
          child: footer,
        ),
      ],
    );

    final body = bodyIsScrollable
        ? SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(edge, 2, edge, 4),
            child: child,
          )
        : Padding(padding: EdgeInsets.fromLTRB(edge, 2, edge, 4), child: child);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: available),
        child: SafeArea(
          top: false,
          child: wholeSheetScrollable
              ? SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...header,
                      Padding(
                        padding: EdgeInsets.fromLTRB(edge, 2, edge, 4),
                        child: child,
                      ),
                      footerArea,
                    ],
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...header,
                    Flexible(child: body),
                    footerArea,
                  ],
                ),
        ),
      ),
    );
  }
}

/// Vertical action stack. Every script-sheet action gets the full sheet width
/// so labels stay readable and tap targets remain comfortable on phones with
/// large text. Secondary actions come first and the primary action stays in
/// the thumb-reachable position at the bottom.
class ScriptSheetActions extends StatelessWidget {
  final Widget primary;
  final List<Widget> secondary;

  const ScriptSheetActions({
    super.key,
    required this.primary,
    this.secondary = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final widget in secondary) ...[widget, const SizedBox(height: 8)],
        primary,
      ],
    );
  }
}

ButtonStyle _actionStyle() => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size.fromHeight(50)),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(vertical: 14, horizontal: 14),
  ),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
);

Widget _actionLabel(String label) => Text(
  label,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  textAlign: TextAlign.center,
);

/// Styled secondary button used by script dialogs.
class ScriptSheetSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const ScriptSheetSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: _actionStyle().copyWith(
        side: WidgetStatePropertyAll(BorderSide(color: cs.outlineVariant)),
      ),
      child: _actionLabel(label),
    );
  }
}

/// Primary action helper.
FilledButton scriptSheetPrimaryButton({
  required String label,
  required VoidCallback? onPressed,
}) {
  return FilledButton(
    onPressed: onPressed,
    style: _actionStyle(),
    child: _actionLabel(label),
  );
}

/// Common "Stop script" confirmation. Returns true when the user really wants
/// to interrupt the running script.
Future<bool> confirmStopScript(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Stop script?'),
      content: const Text(
        'The script and its remote commands will be interrupted. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Keep running'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Stop script'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Copy action with inline success feedback. A root-level snackbar would be
/// painted behind the modal sheet, so the button itself briefly confirms that
/// the clipboard was updated.
class ScriptCopyButton extends StatefulWidget {
  final String label;
  final Future<void> Function() onCopy;

  const ScriptCopyButton({
    super.key,
    required this.label,
    required this.onCopy,
  });

  @override
  State<ScriptCopyButton> createState() => _ScriptCopyButtonState();
}

class _ScriptCopyButtonState extends State<ScriptCopyButton> {
  Timer? _resetTimer;
  bool _copied = false;

  Future<void> _copy() async {
    await widget.onCopy();
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScriptSheetSecondaryButton(
      label: _copied ? 'Copied' : widget.label,
      onPressed: _copy,
    );
  }
}
