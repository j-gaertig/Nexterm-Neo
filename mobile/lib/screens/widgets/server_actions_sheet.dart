import 'package:flutter/material.dart';

import '../../models/server.dart';
import '../../utils/app_icons.dart';

/// One row in the long-press action menu for a server.
class ServerAction {
  const ServerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Builds the action list for [server] in display order.
///
/// Visibility rules mirror the server capabilities: quick actions are only
/// available for regular servers, scripts additionally require an SSH server
/// with an identity, and Wake-On-LAN requires a MAC address on an enabled
/// entry.
List<ServerAction> buildServerActions(
  Server server, {
  required VoidCallback onConnect,
  required VoidCallback onRunScript,
  required VoidCallback onQuickConnect,
  required VoidCallback onWakeOnLan,
  required VoidCallback onEdit,
  required VoidCallback onDuplicate,
  required VoidCallback onToggleDisabled,
  required VoidCallback onDelete,
}) {
  final showQuick = server.isServer && !server.isPve;
  return [
    ServerAction(
      icon: AppIcons.connection,
      label: 'Connect',
      onTap: onConnect,
    ),
    if (showQuick &&
        (server.identities?.isNotEmpty == true) &&
        server.protocol?.toLowerCase() == 'ssh')
      ServerAction(
        icon: AppIcons.codeBracesBox,
        label: 'Run Script',
        onTap: onRunScript,
      ),
    if (showQuick)
      ServerAction(
        icon: AppIcons.cursorDefaultClick,
        label: 'Quick Connect',
        onTap: onQuickConnect,
      ),
    if (server.canWakeOnLan && !server.disabled)
      ServerAction(
        icon: AppIcons.powerPlug,
        label: 'Wake-On-LAN',
        onTap: onWakeOnLan,
      ),
    if (showQuick)
      ServerAction(
        icon: AppIcons.pencilOutline,
        label: 'Edit',
        onTap: onEdit,
      ),
    ServerAction(
      icon: AppIcons.contentCopy,
      label: 'Duplicate',
      onTap: onDuplicate,
    ),
    ServerAction(
      icon: server.disabled ? AppIcons.checkCircle : AppIcons.serverOff,
      label: server.disabled ? 'Enable' : 'Disable',
      onTap: onToggleDisabled,
    ),
    ServerAction(
      icon: AppIcons.trashCanOutline,
      label: 'Delete',
      onTap: onDelete,
    ),
  ];
}

/// Shows the long-press action menu for [server].
///
/// The sheet is capped at 85% of the screen height and the action list scrolls
/// independently of the fixed header, so every action stays reachable on short
/// screens or when the server exposes many actions.
Future<void> showServerActionsSheet(
  BuildContext context,
  Server server, {
  required IconData icon,
  required List<ServerAction> actions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ServerActionsSheet(
      server: server,
      icon: icon,
      actions: actions,
    ),
  );
}

class ServerActionsSheet extends StatelessWidget {
  const ServerActionsSheet({
    super.key,
    required this.server,
    required this.icon,
    required this.actions,
  });

  final Server server;
  final IconData icon;
  final List<ServerAction> actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: cs.onPrimaryContainer, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          server.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (server.ip.isNotEmpty && server.ip != 'N/A')
                          Text(
                            server.ip,
                            style: TextStyle(fontSize: 12, color: cs.outline),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final action in actions) _ActionItem(action: action),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({required this.action});

  final ServerAction action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          action.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(action.icon, size: 22, color: cs.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  action.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
