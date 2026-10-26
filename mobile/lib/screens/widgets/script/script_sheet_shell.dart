import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../utils/app_icons.dart';
import 'script_sheet_result.dart';

/// Shared visual container for every script dialog. Keeps the header, script
/// context, scrollable body, and action area consistent and safe with the
/// keyboard, small screens, and large text.
class ScriptSheetShell extends StatelessWidget {
  final String title;
  final IconData icon;
  final ScriptSheetContext? contextInfo;
  final Widget child;
  final Widget footer;
  final bool bodyIsScrollable;
  final bool wholeSheetScrollable;

  const ScriptSheetShell({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    required this.footer,
    this.contextInfo,
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
    final description = contextInfo?.description ?? '';
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(compact ? 6 : 8),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: cs.onPrimaryContainer,
                size: compact ? 16 : 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!compact && description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(fontSize: 12, color: cs.outline),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: compact ? 6 : 10),
    ];

    final footerArea = Padding(
      padding: EdgeInsets.fromLTRB(
        edge,
        compact ? 6 : 10,
        edge,
        compact ? 8 : 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: cs.outlineVariant),
          SizedBox(height: compact ? 8 : 12),
          footer,
        ],
      ),
    );

    final body = bodyIsScrollable
        ? SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(edge, 2, edge, 4),
            child: child,
          )
        : child;

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

/// Responsive action row: side-by-side on normal phones, stacked when space is
/// tight or the system text scale is large. The primary action always gets the
/// widest area and is placed last on narrow screens (thumb reach).
class ScriptSheetActions extends StatelessWidget {
  final Widget primary;
  final List<Widget> secondary;
  final bool? stackOverride;

  const ScriptSheetActions({
    super.key,
    required this.primary,
    this.secondary = const [],
    this.stackOverride,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    final stack =
        stackOverride ?? (width < 380 || scale > 1.2 || secondary.length > 2);

    if (stack) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final widget in secondary) ...[
            widget,
            const SizedBox(height: 8),
          ],
          primary,
        ],
      );
    }
    return Row(
      children: [
        for (final widget in secondary) ...[
          Expanded(child: widget),
          const SizedBox(width: 8),
        ],
        Expanded(flex: 2, child: primary),
      ],
    );
  }
}

/// Styled secondary button used by script dialogs.
class ScriptSheetSecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const ScriptSheetSecondaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      side: BorderSide(color: cs.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    final child = Text(
      label,
      maxLines: 2,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
    );
    if (icon == null) {
      return OutlinedButton(onPressed: onPressed, style: style, child: child);
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon, size: 16),
      label: child,
    );
  }
}

/// Primary action helper.
FilledButton scriptSheetPrimaryButton({
  required String label,
  required VoidCallback? onPressed,
  IconData? icon,
}) {
  final style = FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
  final child = Text(
    label,
    maxLines: 2,
    textAlign: TextAlign.center,
    overflow: TextOverflow.ellipsis,
  );
  if (icon == null) {
    return FilledButton(onPressed: onPressed, style: style, child: child);
  }
  return FilledButton.icon(
    onPressed: onPressed,
    style: style,
    icon: Icon(icon, size: 16),
    label: child,
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

IconData scriptPromptIcon(bool password) =>
    password ? AppIcons.lockOutline : AppIcons.codeBraces;

/// Copy action with inline success feedback. A root-level snackbar would be
/// painted behind the modal sheet, so the button itself briefly confirms that
/// the clipboard was updated.
class ScriptCopyButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Future<void> Function() onCopy;

  const ScriptCopyButton({
    super.key,
    required this.label,
    required this.onCopy,
    this.icon,
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
      icon: _copied ? AppIcons.check : widget.icon,
      onPressed: _copy,
    );
  }
}

/// Compact per-value copy button with the same inline feedback.
class ScriptCopyIconButton extends StatefulWidget {
  final Future<void> Function() onCopy;
  final String tooltip;

  const ScriptCopyIconButton({
    super.key,
    required this.onCopy,
    this.tooltip = 'Copy value',
  });

  @override
  State<ScriptCopyIconButton> createState() => _ScriptCopyIconButtonState();
}

class _ScriptCopyIconButtonState extends State<ScriptCopyIconButton> {
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
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        _copied ? AppIcons.check : AppIcons.contentCopy,
        size: 16,
        color: _copied ? cs.primary : cs.outline,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      tooltip: _copied ? 'Copied' : widget.tooltip,
      onPressed: _copy,
    );
  }
}
