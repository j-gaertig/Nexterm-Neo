import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/app_icons.dart';
import '../../../utils/script_protocol.dart';
import 'script_sheet_result.dart';
import 'script_sheet_shell.dart';

/// Key/value summary, mirroring the web `SummaryDialog`: pairs are parsed from
/// the flat data list, URLs become tappable links, and values are copyable.
/// Closing (button or system back) sends `input_response` with
/// `value: "closed"` so the script never hangs on a dismissed sheet.
Future<ScriptSheetResult?> showScriptSummarySheet(
  BuildContext context,
  ScriptSummaryEvent event, {
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
    builder: (_) => ScriptSummarySheet(event: event, contextInfo: contextInfo),
  );
}

class ScriptSummarySheet extends StatelessWidget {
  final ScriptSummaryEvent event;
  final ScriptSheetContext? contextInfo;

  const ScriptSummarySheet({super.key, required this.event, this.contextInfo});

  List<MapEntry<String, String>> get _pairs {
    final pairs = <MapEntry<String, String>>[];
    final data = event.data;
    for (var i = 0; i + 1 < data.length; i += 2) {
      if (data[i].isNotEmpty) {
        pairs.add(MapEntry(data[i], data[i + 1]));
      }
    }
    return pairs;
  }

  bool _isUrl(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null) return false;
    return uri.scheme == 'http' ||
        uri.scheme == 'https' ||
        uri.scheme == 'mailto';
  }

  void _close(BuildContext context) {
    Navigator.pop(context, const ScriptClosedResult());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pairs = _pairs;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(context);
      },
      child: ScriptSheetShell(
        title: event.title.isEmpty ? 'Script Summary' : event.title,
        icon: AppIcons.informationOutline,
        contextInfo: contextInfo,
        footer: ScriptSheetActions(
          primary: scriptSheetPrimaryButton(
            label: 'Close',
            icon: AppIcons.check,
            onPressed: () => _close(context),
          ),
          secondary: [
            if (pairs.isNotEmpty)
              ScriptCopyButton(
                label: 'Copy all',
                icon: AppIcons.contentCopy,
                onCopy: () {
                  final text = pairs
                      .map((pair) => '${pair.key}: ${pair.value}')
                      .join('\n');
                  return Clipboard.setData(
                    ClipboardData(
                      text:
                          '${event.title}\n${'=' * event.title.length}\n\n$text',
                    ),
                  );
                },
              ),
          ],
        ),
        child: pairs.isEmpty
            ? Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'No summary data available',
                  style: TextStyle(fontSize: 13, color: cs.outline),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < pairs.length; i++) ...[
                    _SummaryRow(
                      pair: pairs[i],
                      isUrl: _isUrl(pairs[i].value),
                      onCopy: () => Clipboard.setData(
                        ClipboardData(text: pairs[i].value),
                      ),
                    ),
                    if (i != pairs.length - 1)
                      Divider(height: 1, color: cs.outlineVariant),
                  ],
                ],
              ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final MapEntry<String, String> pair;
  final bool isUrl;
  final Future<void> Function() onCopy;

  const _SummaryRow({
    required this.pair,
    required this.isUrl,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    final width = MediaQuery.sizeOf(context).width;
    final stacked = width < 380 || scale > 1.2;

    final key = Text(
      pair.key,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: cs.outline,
      ),
    );
    final valueStyle = TextStyle(
      fontSize: 13,
      height: 1.35,
      color: isUrl ? cs.primary : cs.onSurface,
      decoration: isUrl ? TextDecoration.underline : null,
      decorationColor: cs.primary,
    );
    final value = isUrl
        ? _SummaryValueLink(value: pair.value, style: valueStyle)
        : Text(pair.value, style: valueStyle);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [key, const SizedBox(height: 3), value],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 120, child: key),
                      Expanded(child: value),
                    ],
                  ),
          ),
          ScriptCopyIconButton(onCopy: onCopy, tooltip: 'Copy ${pair.key}'),
        ],
      ),
    );
  }
}

/// Tappable URL value that reports launch failures inline instead of using a
/// snackbar hidden behind the modal sheet.
class _SummaryValueLink extends StatefulWidget {
  final String value;
  final TextStyle style;

  const _SummaryValueLink({required this.value, required this.style});

  @override
  State<_SummaryValueLink> createState() => _SummaryValueLinkState();
}

class _SummaryValueLinkState extends State<_SummaryValueLink> {
  bool _failed = false;

  Future<void> _open() async {
    final uri = Uri.tryParse(widget.value.trim());
    if (uri == null) return;
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    setState(() => _failed = !opened);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(widget.value.trim());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          link: true,
          linkUrl: uri,
          child: InkWell(
            onTap: _open,
            borderRadius: BorderRadius.circular(4),
            child: Text(widget.value, style: widget.style),
          ),
        ),
        if (_failed) ...[
          const SizedBox(height: 4),
          Text(
            'Could not open link',
            style: TextStyle(fontSize: 11, color: cs.error),
          ),
        ],
      ],
    );
  }
}
