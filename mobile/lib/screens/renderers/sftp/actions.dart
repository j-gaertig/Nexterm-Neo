part of '../sftp_renderer.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _SftpActions on _SftpRendererState {
  void _pushEditor(SftpEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SftpCodeEditorScreen(
          sessionId: _sessionId,
          remotePath: _remotePath(entry.name),
          token: widget.token,
        ),
      ),
    );
  }

  void _openInEditor(SftpEntry entry) {
    if (entry.isDir) return;
    if (entry.size > 5242880) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Large file'),
          content: Text('This file is ${entry.formattedSize}. Open it anyway?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _pushEditor(entry);
              },
              child: const Text('Open'),
            ),
          ],
        ),
      );
      return;
    }
    _pushEditor(entry);
  }

  void _showEntryActions(SftpEntry entry) {
    final base = _currentPath;
    final sheetSid = _sessionId;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    _getFileIcon(entry),
                    color: entry.isDir
                        ? Theme.of(ctx).colorScheme.primary
                        : Theme.of(ctx).colorScheme.onSurfaceVariant,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!entry.isDir)
                          Text(
                            entry.formattedSize,
                            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (!entry.isDir)
              ListTile(
                leading: Icon(AppIcons.openInNew),
                title: const Text('Open'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openEntry(entry, base, sheetSid);
                },
              ),
            if (!entry.isDir)
              ListTile(
                leading: Icon(AppIcons.fileCodeOutline),
                title: const Text('Open in Editor'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openInEditor(entry);
                },
              ),
            ListTile(
              leading: Icon(AppIcons.downloadOutline),
              title: const Text('Download'),
              onTap: () {
                Navigator.pop(ctx);
                if (entry.isDir) {
                  _downloadFolder(entry, base, sheetSid);
                } else {
                  _downloadFile(entry, base, sheetSid);
                }
              },
            ),
            if (entry.isDir &&
                widget.session.server.protocol?.toLowerCase() == 'ssh' &&
                !widget.session.server.isPve)
              ListTile(
                leading: Icon(AppIcons.console),
                title: const Text('Open Terminal Here'),
                onTap: _openingTerminal
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _openTerminalHere(entry);
                      },
              ),
            ListTile(
              leading: Icon(AppIcons.pencilOutline),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(entry, base, sheetSid);
              },
            ),
            ListTile(
              leading: Icon(
                AppIcons.deleteOutline,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                'Delete',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _showDeleteConfirmation([entry], base, sheetSid);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _terminalStartPath(String sftpPath) {
    final match = RegExp(r'^/([A-Za-z]:(/.*)?)$').firstMatch(sftpPath);
    if (match == null) return sftpPath;
    final drive = match.group(1)!;
    return drive.length == 2 ? '$drive/' : drive;
  }

  Future<void> _openTerminalHere(SftpEntry entry) async {
    if (_openingTerminal) return;
    setState(() => _openingTerminal = true);
    final path = _terminalStartPath(_remotePath(entry.name));
    try {
      await widget.sessionManager.createTerminalSession(
        token: widget.token,
        server: widget.session.server,
        startPath: path,
      );
    } catch (e) {
      if (mounted) {
        final msg = e.toString().toLowerCase().contains('disabled')
            ? '${widget.session.server.name} is disabled'
            : friendlyApiError(e, fallback: 'Failed to open terminal.');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _openingTerminal = false);
    }
  }

  void _showAddMenu() {
    final base = _currentPath;
    final menuSid = _sessionId;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(AppIcons.folderPlusOutline),
              title: const Text('New Folder'),
              onTap: () {
                Navigator.pop(ctx);
                _showCreateFolderDialog(base, menuSid);
              },
            ),
            ListTile(
              leading: Icon(AppIcons.uploadOutline),
              title: const Text('Upload File'),
              onTap: () {
                Navigator.pop(ctx);
                _uploadFile(base, menuSid);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(SftpEntry entry) {
    if (entry.isDir) return AppIcons.folder;
    if (entry.isSymlink) return AppIcons.linkVariant;
    switch (entry.extension) {
      case 'txt':
      case 'md':
      case 'log':
        return AppIcons.fileDocumentOutline;
      case 'pdf':
        return AppIcons.filePdfBox;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'svg':
        return AppIcons.fileImageOutline;
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'mkv':
        return AppIcons.fileVideoOutline;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'ogg':
        return AppIcons.fileMusicOutline;
      case 'zip':
      case 'tar':
      case 'gz':
      case 'bz2':
      case 'xz':
      case '7z':
      case 'rar':
        return AppIcons.zipBoxOutline;
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
      case 'toml':
        return AppIcons.codeJson;
      case 'js':
      case 'ts':
      case 'py':
      case 'dart':
      case 'java':
      case 'c':
      case 'cpp':
      case 'h':
      case 'rs':
      case 'go':
      case 'rb':
      case 'php':
      case 'sh':
      case 'bash':
        return AppIcons.fileCodeOutline;
      case 'conf':
      case 'cfg':
      case 'ini':
      case 'env':
        return AppIcons.fileCogOutline;
      case 'db':
      case 'sqlite':
      case 'sql':
        return AppIcons.databaseOutline;
      default:
        return AppIcons.fileOutline;
    }
  }

  Color _getFileIconColor(SftpEntry entry, ThemeData theme) {
    if (entry.isDir) return theme.colorScheme.primary;
    if (entry.isSymlink) return theme.colorScheme.tertiary;
    switch (entry.extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'svg':
        return Colors.pink;
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'mkv':
        return Colors.purple;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'ogg':
        return Colors.orange;
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
      case 'rar':
        return Colors.amber;
      case 'pdf':
        return Colors.red;
      default:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
