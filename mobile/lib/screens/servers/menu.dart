part of '../servers_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Long-press menus for servers and folders (mirrors the web context menu).
extension _ServersMenu on ServersScreenState {
  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// Returns the identity to use for [server]. With several identities the
  /// user chooses; with one (or none) no question is asked. `null` with
  /// [cancelled] means the picker was dismissed.
  Future<({int? id, bool cancelled})> _pickIdentity(Server server) async {
    final ids = server.identities ?? const <int>[];
    if (ids.length <= 1) return (id: ids.firstOrNull, cancelled: false);
    final token = widget.authManager.sessionToken;
    if (token == null) return (id: null, cancelled: true);
    final picked = await showIdentityPickerSheet(
      context,
      server: server,
      token: token,
    );
    return (id: picked, cancelled: picked == null);
  }

  Future<void> _connectFromMenu(Server server) async {
    final identity = await _pickIdentity(server);
    if (identity.cancelled || !mounted) return;
    _connectToServer(server, identityId: identity.id);
  }

  Future<void> _openSftpFromMenu(Server server) async {
    final identity = await _pickIdentity(server);
    if (identity.cancelled || !mounted) return;
    await _initiateConnection(
      server,
      type: ConnectionType.sftp,
      identityId: identity.id,
    );
  }

  Future<void> _openBrowserFromMenu(Server server) async {
    final identity = await _pickIdentity(server);
    if (identity.cancelled || !mounted) return;
    await _initiateConnection(
      server,
      type: ConnectionType.guacamole,
      identityId: identity.id,
      browser: true,
    );
  }

  Future<void> _editNotes(Server server) async {
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    final saved = await showServerNotesSheet(
      context,
      server: server,
      token: token,
    );
    if (saved == true) _refreshData();
  }

  Future<void> _editTags(Server server) async {
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    final changed = await showServerTagsSheet(
      context,
      server: server,
      token: token,
    );
    if (changed == true) _refreshData();
  }

  Future<void> _runPveAction(Server server, String action) async {
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    try {
      await ServerActionsService.pveAction(
        token: token,
        entryId: server.id,
        action: action,
      );
      _toast('${server.name}: $action requested');
      _refreshData();
    } catch (e) {
      _toast(
        friendlyApiError(e, fallback: 'Could not $action ${server.name}.'),
      );
    }
  }

  void _showServerMenu(Server server) {
    showServerActionsSheet(
      context,
      server,
      icon: _serverIcon(server),
      actions: buildServerActions(
        server,
        onConnect: () => _connectFromMenu(server),
        onOpenSftp: () => _openSftpFromMenu(server),
        onOpenBrowser: () => _openBrowserFromMenu(server),
        onRunScript: () => _runScript(server),
        onQuickConnect: () => _quickConnect(server),
        onWakeOnLan: () => _wakeServer(server),
        onNotes: () => _editNotes(server),
        onEdit: () => _editServer(server),
        onDuplicate: () => _duplicateServer(server),
        onTags: () => _editTags(server),
        onToggleDisabled: () => _toggleServerDisabled(server),
        onPveAction: (action) => _runPveAction(server, action),
        onDelete: () => _deleteServer(server),
      ),
    );
  }

  // --- Folders ---------------------------------------------------------------

  int? _folderIdInt(ServerFolder folder) =>
      folder.isOrganization ? null : _serverIdInt(folder.id);

  int? _folderOrganizationId(ServerFolder folder) {
    if (folder.isOrganization) return _organizationIdFromFolder(folder);
    final org = folder.organizationId;
    if (org == null) return null;
    return org is int ? org : int.tryParse(org.toString());
  }

  Future<void> _createFolderIn(ServerFolder? parent) async {
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    final name = await showNameDialog(
      context,
      title: 'New folder',
      label: 'Folder name',
      confirmLabel: 'Create',
    );
    if (name == null || !mounted) return;
    try {
      await ServerActionsService.createFolder(
        token: token,
        name: name,
        parentId: parent == null ? null : _folderIdInt(parent),
        organizationId: parent == null ? null : _folderOrganizationId(parent),
      );
      _refreshData();
    } catch (e) {
      _toast(friendlyApiError(e, fallback: 'Could not create the folder.'));
    }
  }

  Future<void> _renameFolder(ServerFolder folder) async {
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    final name = await showNameDialog(
      context,
      title: 'Rename folder',
      label: 'Folder name',
      initial: folder.name,
      confirmLabel: 'Rename',
    );
    if (name == null || name == folder.name || !mounted) return;
    try {
      await ServerActionsService.renameFolder(
        token: token,
        folderId: folder.id,
        name: name,
      );
      _refreshData();
    } catch (e) {
      _toast(friendlyApiError(e, fallback: 'Could not rename the folder.'));
    }
  }

  Future<void> _deleteFolder(ServerFolder folder) async {
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete folder?'),
        content: Text(
          '"${folder.name}" and everything inside it will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ServerActionsService.deleteFolder(
        token: token,
        folderId: folder.id,
      );
      _toast('${folder.name} deleted');
      _refreshData();
    } catch (e) {
      _toast(friendlyApiError(e, fallback: 'Could not delete the folder.'));
    }
  }

  void _showFolderMenu(ServerFolder folder) {
    // Folders synced from an integration (for example Proxmox) are managed
    // there; only regular folders and organisations offer edit actions.
    if (folder.isPveNode) return;
    final option = _folderOptionOf(folder);
    final isOrg = folder.isOrganization;
    showActionsSheet(
      context,
      title: folder.name,
      subtitle: isOrg ? 'Organization' : 'Folder',
      icon: isOrg ? AppIcons.brandDomain : AppIcons.brandFolder,
      actions: [
        ServerAction(
          icon: AppIcons.plus,
          label: 'New server here',
          onTap: () => createServer(inFolder: option),
        ),
        ServerAction(
          icon: AppIcons.folderPlusOutline,
          label: 'New folder',
          onTap: () => _createFolderIn(folder),
        ),
        if (!isOrg) ...[
          ServerAction(
            icon: AppIcons.textCursorInput,
            label: 'Rename folder',
            onTap: () => _renameFolder(folder),
            dividerBefore: true,
          ),
          ServerAction(
            icon: AppIcons.folderRemove,
            label: 'Delete folder',
            onTap: () => _deleteFolder(folder),
            danger: true,
            dividerBefore: true,
          ),
        ],
      ],
    );
  }
}
