import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/app_icons.dart';
import '../../../utils/script_protocol.dart';
import 'script_sheet_result.dart';

/// Key/value summary, mirroring the web `SummaryDialog`: pairs are parsed
/// from the flat data list, URLs become tappable links, values are copyable.
/// Closing sends `input_response` with `value: "closed"`.
Future<ScriptSheetResult?> showScriptSummarySheet(BuildContext context, ScriptSummaryEvent event) {
  return showModalBottomSheet<ScriptSheetResult>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => ScriptSummarySheet(event: event),
  );
}

class ScriptSummarySheet extends StatelessWidget {
  final ScriptSummaryEvent event;

  const ScriptSummarySheet({super.key, required this.event});

  List<MapEntry<String, String>> get _pairs {
    final pairs = <MapEntry<String, String>>[];
    final data = event.data;
    for (var i = 0; i + 1 < data.length; i += 2) {
      if (data[i].isNotEmpty && data[i + 1].isNotEmpty) {
        pairs.add(MapEntry(data[i], data[i + 1]));
      }
    }
    return pairs;
  }

  bool _isUrl(String text) => Uri.tryParse(text)?.hasScheme ?? false;

  void _copy(BuildContext context, String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$label copied to clipboard'),
        behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pairs = _pairs;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
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
              child: Icon(AppIcons.informationOutline, color: cs.onPrimaryContainer, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(event.title, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis)),
          ]),
        ),
        const SizedBox(height: 10),
        Flexible(
          child: pairs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('No summary data available', style: TextStyle(fontSize: 13, color: cs.outline)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: pairs.length,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  itemBuilder: (_, i) {
                    final pair = pairs[i];
                    final isUrl = _isUrl(pair.value);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(
                          width: 120,
                          child: Text(pair.key,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.outline)),
                        ),
                        Expanded(child: GestureDetector(
                          onTap: isUrl ? () => _openUrl(context, pair.value) : null,
                          child: Text(pair.value,
                              style: TextStyle(fontSize: 13,
                                  color: isUrl ? cs.primary : cs.onSurface,
                                  decoration: isUrl ? TextDecoration.underline : null,
                                  decorationColor: cs.primary),
                              softWrap: true),
                        )),
                        IconButton(
                          icon: Icon(AppIcons.contentCopy, size: 16, color: cs.outline),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                          tooltip: 'Copy value',
                          onPressed: () => _copy(context, pair.value, pair.key),
                        ),
                      ]),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Row(children: [
            if (pairs.isNotEmpty) ...[
              Expanded(child: OutlinedButton.icon(
                onPressed: () {
                  final text = pairs.map((p) => '${p.key}: ${p.value}').join('\n');
                  _copy(context, '${event.title}\n${'=' * event.title.length}\n\n$text', 'Summary');
                },
                icon: const Icon(AppIcons.fileDocumentOutline, size: 16),
                label: const Text('Copy All'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: cs.outlineVariant),
                ),
              )),
              const SizedBox(width: 8),
            ],
            Expanded(child: FilledButton(
              onPressed: () => Navigator.pop(context, const ScriptClosedResult()),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              child: const Text('Close'),
            )),
          ]),
        ),
      ]),
    );
  }

  void _openUrl(BuildContext context, String url) {
    // Mirror of the web `openExternalUrl`. Dead links still attempt to open;
    // failures surface as a toast.
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to open link'),
          behavior: SnackBarBehavior.floating));
      }
      return false;
    });
  }
}
