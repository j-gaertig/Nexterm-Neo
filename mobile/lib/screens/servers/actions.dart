part of '../servers_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ServersActions on ServersScreenState {
  ServerFolder? _organizationForServer(Server server) {
    final id = _serverIdInt(server.id);
    if (id == null) return null;
    return _findOrganizationForServer(id, folders);
  }

  int? _organizationIdFromFolder(ServerFolder? folder) {
    if (folder == null) return null;
    final direct = folder.organizationId;
    if (direct is int) return direct;
    if (direct != null) {
      final parsed = int.tryParse(direct.toString());
      if (parsed != null) return parsed;
    }
    final match = RegExp(r'(\d+)$').firstMatch(folder.id.toString());
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  Future<void> _initiateConnection(
    Server server, {
    ConnectionType type = ConnectionType.terminal,
    Map<String, dynamic>? directIdentity,
    RunScriptSelection? script,
  }) async {
    if (server.disabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${server.name} is disabled'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final token = widget.authManager.sessionToken;
    if (token == null) return;

    String? connectionReason;
    if (_requiresConnectionReason(server)) {
      connectionReason = await showConnectionReasonDialog(context, server.name);
      if (connectionReason == null || !mounted) return;
    }

    try {
      final AppSession opened;
      if (script != null) {
        opened = await widget.sessionManager.createScriptSession(
          token: token,
          server: server,
          scriptId: script.scriptId,
          scriptName: script.scriptName,
          identityId: script.identityId,
          connectionReason: connectionReason,
        );
      } else {
        opened = switch (type) {
          ConnectionType.guacamole =>
            await widget.sessionManager.createGuacSession(
              token: token,
              server: server,
              directIdentity: directIdentity,
              connectionReason: connectionReason,
            ),
          ConnectionType.terminal =>
            await widget.sessionManager.createTerminalSession(
              token: token,
              server: server,
              directIdentity: directIdentity,
              connectionReason: connectionReason,
            ),
          ConnectionType.sftp => await widget.sessionManager.createSftpSession(
            token: token,
            server: server,
            directIdentity: directIdentity,
            connectionReason: connectionReason,
          ),
        };
      }
      if (mounted) widget.onSessionOpened?.call(opened.sessionId);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      final msg = raw.toLowerCase().contains('disabled')
          ? '${server.name} is disabled'
          : friendlyApiError(
              e,
              fallback: script != null
                  ? 'Failed to start the script on ${server.name}.'
                  : 'Failed to connect to ${server.name}.',
            );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    }
  }

  bool _requiresConnectionReason(Server server) {
    final id = _serverIdInt(server.id);
    if (id == null) return false;
    return _findOrganizationForServer(id, folders)?.requireConnectionReason ??
        false;
  }

  ServerFolder? _findOrganizationForServer(
    int serverId,
    List<dynamic> items, [
    ServerFolder? currentOrg,
  ]) {
    for (final item in items) {
      if (item is Server) {
        if (_serverIdInt(item.id) == serverId) return currentOrg;
      } else if (item is ServerFolder) {
        final org = item.isOrganization ? item : currentOrg;
        final found = _findOrganizationForServer(serverId, [
          ...item.allServers,
          ...item.allFolders,
        ], org);
        if (found != null) return found;
      }
    }
    return null;
  }

  int? _serverIdInt(dynamic id) => id is int ? id : int.tryParse(id.toString());

  void _showServerMenu(Server server) {
    showServerActionsSheet(
      context,
      server,
      icon: _serverIcon(server),
      actions: buildServerActions(
        server,
        onConnect: () => _connectToServer(server),
        onRunScript: () => _runScript(server),
        onQuickConnect: () => _quickConnect(server),
        onWakeOnLan: () => _wakeServer(server),
        onEdit: () => _editServer(server),
        onDuplicate: () => _duplicateServer(server),
        onToggleDisabled: () => _toggleServerDisabled(server),
        onDelete: () => _deleteServer(server),
      ),
    );
  }

  Future<void> _quickConnect(Server server) async {
    if (server.disabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${server.name} is disabled'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (server.isPve) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quick Connect is not supported for Proxmox entries'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (server.protocol?.toLowerCase() == 'telnet') {
      _initiateConnection(server);
      return;
    }

    final directIdentity = await showQuickConnectSheet(context, server);
    if (directIdentity == null || !mounted) return;

    final isFileProtocolForQuickConnect = const {
      'sftp',
      'ftp',
      'ftps',
    }.contains(server.protocol?.toLowerCase());
    _initiateConnection(
      server,
      type: ServerService.isGuacamoleProtocol(server.protocol)
          ? ConnectionType.guacamole
          : isFileProtocolForQuickConnect
          ? ConnectionType.sftp
          : ConnectionType.terminal,
      directIdentity: directIdentity,
    );
  }

  Future<void> _wakeServer(Server server) async {
    if (server.disabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${server.name} is disabled'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final token = widget.authManager.sessionToken;
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Not authenticated'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final entryId = server.id;
    if (entryId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send magic packet: missing server id'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    try {
      await ServerService.wakeServer(token: token, entryId: entryId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Magic packet sent to ${server.name}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyApiError(e, fallback: 'Failed to send magic packet.'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<FolderOption> _folderOptions() {
    final out = <FolderOption>[];
    void walk(List<dynamic> items) {
      for (final item in items) {
        if (item is ServerFolder) {
          if (item.type == 'folder') {
            out.add(
              FolderOption(
                id: item.id,
                name: item.name,
                type: item.type,
                organizationId: item.organizationId,
              ),
            );
          }
          walk(item.allFolders);
        }
      }
    }

    walk(folders);
    return out;
  }

  FolderOption? _expandedFolderContext() {
    if (_expanded.isEmpty) return null;
    final byKey = <String, FolderOption>{};
    final depth = <String, int>{};
    void walk(List<dynamic> items, int level) {
      for (final item in items) {
        if (item is ServerFolder) {
          final key = _folderKey(item);
          if (!byKey.containsKey(key) || level > (depth[key] ?? -1)) {
            byKey[key] = _folderOptionOf(item);
            depth[key] = level;
          }
          walk(item.allFolders, level + 1);
        }
      }
    }

    walk(folders, 0);
    FolderOption? match;
    int best = -1;
    for (final key in _expanded) {
      if (byKey.containsKey(key) && (depth[key] ?? 0) > best) {
        match = byKey[key];
        best = depth[key] ?? 0;
      }
    }
    return match;
  }

  FolderOption _folderOptionOf(ServerFolder folder) {
    if (folder.isOrganization) {
      dynamic orgId = folder.organizationId;
      if (orgId == null && folder.id != null) {
        orgId = int.tryParse(folder.id.toString().split('-').last) ?? folder.id;
      }
      return FolderOption(
        id: null,
        name: folder.name,
        type: 'organization',
        organizationId: orgId ?? folder.id,
      );
    }
    return FolderOption(
      id: folder.id,
      name: folder.name,
      type: folder.type,
      organizationId: folder.organizationId,
    );
  }

  FolderOption? _parentFolderOf(dynamic serverId) {
    FolderOption? search(List<dynamic> items) {
      for (final item in items) {
        if (item is ServerFolder) {
          if (item.allServers.any(
            (s) => s.id.toString() == serverId.toString(),
          )) {
            return _folderOptionOf(item);
          }
          final nested = search(item.allFolders);
          if (nested != null) return nested;
        }
      }
      return null;
    }

    return search(folders);
  }

  Future<void> _editServer(Server server) async {
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    if (!mounted) return;
    final parent = _parentFolderOf(server.id);
    final changed = await pushPage(
      context,
      (_) => ServerEditorScreen(
        token: token,
        editServerId: server.id,
        folderOptions: _folderOptions(),
        initialFolderId: parent?.id,
        initialOrganizationId: parent?.organizationId,
      ),
    );
    if (changed == true) _refreshData();
  }

  Future<void> _duplicateServer(Server server) async {
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    try {
      await ServerEditorService.duplicateEntry(
        token: token,
        entryId: server.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${server.name} duplicated'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _refreshData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyApiError(e, fallback: 'Duplicate failed.')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleServerDisabled(Server server) async {
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    final disabled = !server.disabled;
    try {
      await ServerEditorService.setEntryDisabled(
        token: token,
        entryId: server.id,
        disabled: disabled,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            disabled ? '${server.name} disabled' : '${server.name} enabled',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _refreshData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyApiError(
              e,
              fallback: disabled ? 'Disable failed.' : 'Enable failed.',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteServer(Server server) async {
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete server?'),
        content: Text('${server.name} will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ServerEditorService.deleteEntry(token: token, entryId: server.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${server.name} deleted'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _refreshData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyApiError(e, fallback: 'Delete failed.')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _connectToServer(Server server) {
    if (server.disabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${server.name} is disabled'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final cs = Theme.of(context).colorScheme;
    if (server.isStopped) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${server.name} is ${server.isPve ? "not running" : "offline"}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final hasIdentities = server.identities?.isNotEmpty == true;
    if (!server.isPve && !hasIdentities) {
      _quickConnect(server);
      return;
    }
    if (ServerService.isGuacamoleProtocol(server.protocol) ||
        server.type == 'pve-qemu') {
      _initiateConnection(server, type: ConnectionType.guacamole);
      return;
    }
    final protocolLower = server.protocol?.toLowerCase();
    final isFileProtocol =
        protocolLower == 'sftp' ||
        protocolLower == 'ftp' ||
        protocolLower == 'ftps';
    if (isFileProtocol) {
      _initiateConnection(server, type: ConnectionType.sftp);
      return;
    }
    final isSSH = protocolLower == 'ssh' && !server.isPve;
    if (!isSSH) {
      _initiateConnection(server);
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSheetHandle(margin: const EdgeInsets.only(top: 12, bottom: 4)),
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
                    child: Icon(
                      _serverIcon(server),
                      color: cs.onPrimaryContainer,
                      size: 18,
                    ),
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
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (server.ip.isNotEmpty && server.ip != 'N/A')
                          Text(
                            server.ip,
                            style: TextStyle(fontSize: 12, color: cs.outline),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _connectionOption(
                      ctx,
                      AppIcons.consoleLine,
                      'Terminal',
                      'SSH session',
                      cs,
                      () {
                        Navigator.pop(ctx);
                        _initiateConnection(server);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _connectionOption(
                      ctx,
                      AppIcons.folderOutline,
                      'SFTP',
                      'File manager',
                      cs,
                      () {
                        Navigator.pop(ctx);
                        _initiateConnection(server, type: ConnectionType.sftp);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _connectionOption(
    BuildContext ctx,
    IconData icon,
    String title,
    String sub,
    ColorScheme cs,
    VoidCallback onTap,
  ) => AppCard(
    onSheet: true,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
    child: Column(
      children: [
        Icon(icon, color: cs.primary, size: 28),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(sub, style: TextStyle(fontSize: 11, color: cs.outline)),
      ],
    ),
  );

  IconData _serverIcon(Server server) {
    final icon = server.icon;
    if (icon != null && icon.startsWith('mdi') && icon.length > 3) {
      final camel = icon.substring(3, 4).toLowerCase() + icon.substring(4);
      final hit = AppIcons.resolveBackendIcon(camel);
      if (hit != null) return hit;
    }
    if (server.type == 'pve-lxc') return AppIcons.brandCube;
    if (server.type == 'pve-qemu') return AppIcons.brandMonitor;
    if (server.type == 'pve-shell') return AppIcons.brandConsole;
    final p = server.protocol?.toLowerCase();
    if (p == 'rdp') return AppIcons.brandWindows;
    if (p == 'vnc') return AppIcons.brandMonitor;
    if (p == 'spice') return AppIcons.brandMonitor;
    if (p == 'ssh' || p == 'telnet') return AppIcons.brandConsole;
    if (p == 'sftp' || p == 'ftp' || p == 'ftps') return AppIcons.folderOutline;
    return AppIcons.brandServer;
  }

  Color _parseColor(String c) =>
      parseTagColor(c, fallback: Theme.of(context).colorScheme.outlineVariant);
}
