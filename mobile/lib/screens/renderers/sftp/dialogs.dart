part of '../sftp_renderer.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _SftpDialogs on _SftpRendererState {
  bool _isValidEntryName(String name) =>
      name.isNotEmpty &&
      name != '.' &&
      name != '..' &&
      !name.contains('/') &&
      !name.contains('\\');

  void _showInvalidNameMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enter a name without slashes.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showRenameDialog(SftpEntry entry, [String? base, String? sheetSid]) {
    final controller = TextEditingController(text: entry.name);
    final dialogBase = base ?? _currentPath;
    final dialogSid = sheetSid ?? _sessionId;
    final dialog = showDialog<void>(
      context: context,
      builder: (ctx) {
        void submit() {
          final newName = controller.text.trim();
          if (newName.isEmpty || newName == entry.name) {
            Navigator.pop(ctx);
            return;
          }
          if (!_isValidEntryName(newName)) {
            _showInvalidNameMessage();
            return;
          }
          Navigator.pop(ctx);
          if (dialogSid != _sessionId) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Session changed, please retry')),
            );
            _refresh();
            return;
          }
          if (dialogBase != _currentPath) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Directory changed, please retry')),
            );
            _refresh();
            return;
          }
          final oldPath = _remotePathIn(dialogBase, entry.name);
          final newPath = _remotePathIn(dialogBase, newName);
          if (_hasUploadingFor(oldPath, dialogSid) ||
              _hasUploadingFor(newPath, dialogSid)) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Upload in progress, please retry shortly'),
              ),
            );
            return;
          }
          _dropPendingFor(oldPath, dialogSid);
          _dropPendingFor(newPath, dialogSid);
          _sendOperation(_SftpOps.renameFile, {
            'path': oldPath,
            'newPath': newPath,
          });
        }

        return AlertDialog(
          title: const Text('Rename'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'[\\/]')),
            ],
            onSubmitted: (_) => submit(),
            decoration: const InputDecoration(
              labelText: 'New name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: submit, child: const Text('Rename')),
          ],
        );
      },
    );
    unawaited(dialog.whenComplete(controller.dispose));
  }

  void _showDeleteConfirmation(
    List<SftpEntry> entries, [
    String? base,
    String? sheetSid,
  ]) {
    if (!widget.sftpSettings.confirmBeforeDelete) {
      _performDelete(entries, base, sheetSid);
      return;
    }
    final count = entries.length;
    final dialogBase = base ?? _currentPath;
    final dialogSid = sheetSid ?? _sessionId;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: Text(
          count == 1
              ? 'Delete "${entries.first.name}"?'
              : 'Delete $count items?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _performDelete(entries, dialogBase, dialogSid);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _performDelete(
    List<SftpEntry> entries, [
    String? base,
    String? sheetSid,
  ]) {
    final snapshot = base ?? _currentPath;
    final actionSid = sheetSid ?? _sessionId;
    if (actionSid != _sessionId) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session changed, please retry')),
      );
      _refresh();
      return;
    }
    if (base != null && base != _currentPath) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Directory changed, please retry')),
      );
      _refresh();
      return;
    }
    for (final entry in entries) {
      final path = _remotePathIn(snapshot, entry.name);
      if (_hasUploadingFor(path, actionSid)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Upload in progress, please retry shortly'),
          ),
        );
        return;
      }
      if (_hasPendingFor(path, actionSid)) {
        _dropPendingFor(path, actionSid);
      }
    }
    for (final entry in entries) {
      final path = _remotePathIn(snapshot, entry.name);
      _dropPendingFor(path, actionSid);
      _sendOperation(
        entry.isDir ? _SftpOps.deleteFolder : _SftpOps.deleteFile,
        {'path': path},
      );
    }
  }

  void _showCreateFolderDialog([String? base, String? sheetSid]) {
    final controller = TextEditingController();
    final dialogBase = base ?? _currentPath;
    final dialogSid = sheetSid ?? _sessionId;
    final dialog = showDialog<void>(
      context: context,
      builder: (ctx) {
        void submit() {
          final name = controller.text.trim();
          if (name.isEmpty) return;
          if (!_isValidEntryName(name)) {
            _showInvalidNameMessage();
            return;
          }
          Navigator.pop(ctx);
          if (dialogSid != _sessionId) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Session changed, please retry')),
            );
            _refresh();
            return;
          }
          if (dialogBase != _currentPath) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Directory changed, please retry')),
            );
            _refresh();
            return;
          }
          final target = _remotePathIn(dialogBase, name);
          if (_hasUploadingFor(target, dialogSid)) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Upload in progress, please retry shortly'),
              ),
            );
            return;
          }
          if (_hasPendingFor(target, dialogSid)) {
            _dropPendingFor(target, dialogSid);
          }
          _sendOperation(_SftpOps.createFolder, {'path': target});
        }

        return AlertDialog(
          title: const Text('New Folder'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'[\\/]')),
            ],
            onSubmitted: (_) => submit(),
            decoration: const InputDecoration(
              labelText: 'Folder name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: submit, child: const Text('Create')),
          ],
        );
      },
    );
    unawaited(dialog.whenComplete(controller.dispose));
  }
}
