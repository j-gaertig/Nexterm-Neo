import 'package:flutter/material.dart';

import '../../widgets/app_ui.dart';
import '../../models/server.dart';
import '../../utils/app_icons.dart';

/// One row in the long-press action menu for a server or folder.
class ServerAction {
  const ServerAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.dividerBefore = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Destructive action, drawn in the error colour.
  final bool danger;

  /// Draws a separator above this row to group related actions.
  final bool dividerBefore;
}

/// Builds the action list for [server] in display order, mirroring the web
/// context menu.
///
/// Visibility rules follow the server capabilities: quick actions only exist
/// for regular servers, SFTP/Browser/scripts additionally need an SSH server
/// with an identity, Wake-On-LAN needs a MAC address on an enabled entry, and
/// Proxmox entries get power actions. Optional callbacks that are `null` hide
/// their action.
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
  VoidCallback? onOpenSftp,
  VoidCallback? onOpenBrowser,
  VoidCallback? onNotes,
  VoidCallback? onTags,
  void Function(String action)? onPveAction,
}) {
  final showQuick = server.isServer && !server.isPve;
  final isSsh = server.protocol?.toLowerCase() == 'ssh';
  final hasIdentities = server.identities?.isNotEmpty == true;
  final canWeb = showQuick && isSsh && hasIdentities;
  final hasNotes = server.notes?.trim().isNotEmpty == true;
  return [
    ServerAction(icon: AppIcons.connection, label: 'Connect', onTap: onConnect),
    if (canWeb && onOpenSftp != null)
      ServerAction(
        icon: AppIcons.folderOpen,
        label: 'Open SFTP',
        onTap: onOpenSftp,
      ),
    if (canWeb && onOpenBrowser != null)
      ServerAction(
        icon: AppIcons.web,
        label: 'Open Browser',
        onTap: onOpenBrowser,
      ),
    if (canWeb)
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
    if (onNotes != null)
      ServerAction(
        icon: AppIcons.noteEdit,
        label: hasNotes ? 'Open notes' : 'Add notes',
        onTap: onNotes,
        dividerBefore: true,
      ),
    if (showQuick)
      ServerAction(
        icon: AppIcons.pencilOutline,
        label: 'Edit',
        onTap: onEdit,
        dividerBefore: onNotes == null,
      ),
    ServerAction(
      icon: AppIcons.contentCopy,
      label: 'Duplicate',
      onTap: onDuplicate,
    ),
    if (onTags != null)
      ServerAction(icon: AppIcons.tag, label: 'Tags', onTap: onTags),
    ServerAction(
      icon: server.disabled ? AppIcons.checkCircle : AppIcons.serverOff,
      label: server.disabled ? 'Enable' : 'Disable',
      onTap: onToggleDisabled,
    ),
    if (server.isPve && onPveAction != null) ...[
      if (server.isRunning && server.type != 'pve-shell') ...[
        ServerAction(
          icon: AppIcons.power,
          label: 'Shut down',
          onTap: () => onPveAction('shutdown'),
          dividerBefore: true,
        ),
        ServerAction(
          icon: AppIcons.stop,
          label: 'Stop',
          onTap: () => onPveAction('stop'),
        ),
      ],
      if (server.status == 'stopped')
        ServerAction(
          icon: AppIcons.play,
          label: 'Start',
          onTap: () => onPveAction('start'),
          dividerBefore: true,
        ),
    ],
    ServerAction(
      icon: AppIcons.trashCanOutline,
      label: 'Delete',
      onTap: onDelete,
      danger: true,
      dividerBefore: true,
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
  return showActionsSheet(
    context,
    title: server.name,
    subtitle: server.ip.isNotEmpty && server.ip != 'N/A' ? server.ip : null,
    icon: icon,
    actions: actions,
    builder: (_) =>
        ServerActionsSheet(server: server, icon: icon, actions: actions),
  );
}

/// Shows an action menu with a custom header (used for folders).
Future<void> showActionsSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required IconData icon,
  required List<ServerAction> actions,
  WidgetBuilder? builder,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder:
        builder ??
        (_) => ActionsSheet(
          title: title,
          subtitle: subtitle,
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
    return ActionsSheet(
      title: server.name,
      subtitle: server.ip.isNotEmpty && server.ip != 'N/A' ? server.ip : null,
      icon: icon,
      actions: actions,
    );
  }
}

class ActionsSheet extends StatelessWidget {
  const ActionsSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.actions,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<ServerAction> actions;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppSheetHandle(),
            AppSheetTitle(title: title, subtitle: subtitle, icon: icon),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final action in actions) ...[
                      if (action.dividerBefore)
                        const AppDivider(indent: 20, endIndent: 20),
                      _ActionItem(action: action),
                    ],
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
    final color = action.danger ? cs.error : cs.primary;
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
              Icon(action.icon, size: 22, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  action.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: action.danger ? cs.error : null,
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
