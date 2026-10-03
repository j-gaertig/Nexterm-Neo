import 'package:flutter/material.dart';
import '../../utils/app_icons.dart';
import '../../utils/server_field_config.dart';

Future<String?> showServerProtocolSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const ServerProtocolSheet(),
  );
}

class ServerProtocolSheet extends StatelessWidget {
  const ServerProtocolSheet({super.key});

  IconData _iconFor(String protocol) {
    switch (protocol) {
      case 'ssh':
      case 'telnet':
        return AppIcons.brandConsole;
      case 'rdp':
        return AppIcons.brandWindows;
      case 'vnc':
        return AppIcons.brandMonitor;
      case 'sftp':
      case 'ftp':
      case 'ftps':
        return AppIcons.folderOutline;
      default:
        return AppIcons.brandServer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text('New server', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Choose a protocol',
              style: tt.bodySmall?.copyWith(color: cs.outline),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: ServerEditorConstants.protocols.length,
              itemBuilder: (_, i) {
                final p = ServerEditorConstants.protocols[i];
                final value = p['value']!;
                final port = ServerEditorConstants.defaultPorts[value] ?? '';
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.pop(context, value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
                            child: Icon(_iconFor(value), color: cs.onPrimaryContainer, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p['label']!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                Text('Default port $port', style: TextStyle(fontSize: 12, color: cs.outline)),
                              ],
                            ),
                          ),
                          Icon(AppIcons.chevronRight, color: cs.outlineVariant, size: 18),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
