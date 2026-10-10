// SFTP file browser for an opened remote session.
//
// Browsing runs over the `/ws/sftp` binary channel (see `sftp_protocol.dart`
// and `server/routes/sftpWS.js`); up/download use the REST endpoints
// (see `server/routes/sftp.js`) with query-token auth.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:nexterm_v2/api/nexterm_api.dart';
import 'package:nexterm_v2/remote/session_opener.dart';
import 'package:nexterm_v2/settings/settings_scope.dart';

import 'file_editor_screen.dart';
import 'sftp_protocol.dart';
import 'sftp_service.dart';
import 'terminal_screen.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen(
      {super.key,
      required this.api,
      required this.sessionToken,
      required this.session,
      this.onSessionExpired});

  final NextermApi api;
  final String sessionToken;
  final RemoteSession session;

  /// Called on HTTP 401 so expired sessions return to login.
  final VoidCallback? onSessionExpired;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  SftpConnection? _connection;
  StreamSubscription<SftpMessage>? _subscription;
  List<SftpEntry> _entries = [];
  String _currentPath = '/';
  String _rootPath = '/';
  bool _loading = true;
  bool _connected = false;
  bool _transferring = false;
  String? _error;
  String _lastRequested = '/';
  Completer<void>? _listCompleter;
  bool _tornDown = false;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    final url = NextermApi.wsUrl(widget.api.baseUrl, '/ws/sftp', {
      'sessionToken': widget.sessionToken,
      'sessionId': widget.session.sessionId,
    });
    final connection = SftpConnection.connect(url);
    _connection = connection;
    _subscription = connection.messages.listen(
      _onMessage,
      onError: _onChannelError,
      onDone: _onChannelDone,
    );
  }

  @override
  void dispose() {
    _tearDown();
    _searchController.dispose();
    super.dispose();
  }

  /// Close the channel and hibernate the server session (best effort,
  /// so it stays reopenable from the sessions sheet).
  void _tearDown() {
    if (_tornDown) return;
    _tornDown = true;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final connection = _connection;
    _connection = null;
    if (connection != null) unawaited(connection.close());
    unawaited(_deleteSessionBestEffort());
  }

  Future<void> _deleteSessionBestEffort() async {
    try {
      await widget.api.hibernateConnection(
          widget.sessionToken, widget.session.sessionId);
    } catch (e) {
      logSftpTransferError(e);
    }
  }

  Future<void> _disconnectAndClose() async {
    _tearDown();
    if (mounted) Navigator.pop(context);
  }

  // -- Inbound frames ----------------------------------------------------

  void _onMessage(SftpMessage message) {
    switch (message.op) {
      case SftpOp.ready:
        _onReady(message);
      case SftpOp.listFiles:
        _onListing(message);
      case SftpOp.error:
        _onRemoteError(message);
      case SftpOp.pathSync:
        final path = message.payload['path'];
        if (path is String && path.isNotEmpty && path != _currentPath) {
          if (!mounted) return;
          setState(() => _currentPath = path);
          _requestList(path);
        }
      default:
        // Acknowledgements for mutating ops: refresh silently.
        _requestList(_currentPath, silent: true);
    }
  }

  void _onReady(SftpMessage message) {
    final path = message.payload['path'];
    final root = message.payload['rootPath'];
    if (!mounted) return;
    setState(() {
      _connected = true;
      _error = null;
      _rootPath = root is String && root.isNotEmpty ? root : '/';
      _currentPath = path is String && path.isNotEmpty ? path : _rootPath;
    });
    _requestList(_currentPath);
  }

  void _onListing(SftpMessage message) {
    _completeListWait();
    if (!mounted) return;
    final echoed = message.payload['path'];
    if (echoed is String &&
        echoed.isNotEmpty &&
        echoed != _currentPath &&
        echoed != _lastRequested) {
      // Stale response for a previously visited directory.
      return;
    }
    setState(() {
      _entries = sortSftpEntries(parseSftpListing(message.payload));
      _loading = false;
      _error = null;
    });
  }

  void _onRemoteError(SftpMessage message) {
    final detail = sftpErrorMessage(message);
    final listPending = _listCompleter != null;
    _completeListWait();
    if (!mounted) return;
    setState(() {
      _error = detail;
      if (listPending) _loading = false;
    });
    _showSnack(detail);
  }

  void _onChannelError(Object error) {
    _completeListWait();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _loading = false;
      _error = 'Connection lost.';
    });
    _showSnack('Connection lost.');
  }

  void _onChannelDone() {
    _completeListWait();
    if (!mounted || _tornDown) return;
    setState(() {
      _connected = false;
      if (_entries.isEmpty) {
        _loading = false;
        _error ??= 'Connection closed.';
      }
    });
    _showSnack('Connection lost.');
  }

  void _completeListWait() {
    final pending = _listCompleter;
    _listCompleter = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  // -- Outbound requests --------------------------------------------------

  void _requestList(String path, {bool silent = false}) {
    final connection = _connection;
    if (connection == null) {
      if (!mounted) return;
      setState(() {
        _error = 'No connection available.';
        _loading = false;
      });
      return;
    }
    _lastRequested = path;
    _completeListWait();
    _listCompleter = Completer<void>();
    if (!silent && mounted) {
      setState(() {
        if (_entries.isEmpty) _loading = true;
        _error = null;
      });
    }
    connection.requestList(path);
  }

  Future<void> _refresh() async {
    if (!_requireLiveConnection()) {
      _completeListWait();
      return;
    }
    _requestList(_currentPath, silent: _entries.isNotEmpty);
    final pending = _listCompleter;
    if (pending != null) {
      await pending.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          if (mounted && !_tornDown) {
            setState(() {
              _error ??= 'Request timed out.';
            });
          }
        },
      );
    }
  }

  /// Guard mutations/transfers against a dead channel with feedback
  /// instead of silently dropping requests.
  bool _requireLiveConnection() {
    if (_connected && _connection != null) return true;
    if (mounted) {
      _showSnack('Connection lost. Pull to refresh to reconnect.');
    }
    return false;
  }

  void _navigateTo(String path) {
    if (path == _currentPath) {
      _requestList(path);
      return;
    }
    setState(() {
      _currentPath = path;
      _error = null;
    });
    _requestList(path);
    _connection?.syncPath(path);
  }

  void _goUp() {
    final parent = sftpParent(_currentPath);
    _navigateTo(
        sftpIsWithin(parent, _rootPath) ? parent : _rootPath);
  }

  // -- Mutations ----------------------------------------------------------

  Future<String?> _askForName({
    required String title,
    required String label,
    required String confirmLabel,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, controller.text.trim()),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _createFolder() async {
    final name = await _askForName(
      title: 'New folder',
      label: 'Folder name',
      confirmLabel: 'Create',
    );
    if (name == null || name.isEmpty || !mounted) return;
    if (!_requireLiveConnection()) return;
    _connection?.createFolder(sftpJoin(_currentPath, name));
  }

  Future<void> _createFile() async {
    final name = await _askForName(
      title: 'New file',
      label: 'File name',
      confirmLabel: 'Create',
    );
    if (name == null || name.isEmpty || !mounted) return;
    if (!_requireLiveConnection()) return;
    _connection?.createFile(sftpJoin(_currentPath, name));
  }

  Future<void> _rename(SftpEntry entry) async {
    final name = await _askForName(
      title: 'Rename',
      label: 'New name',
      confirmLabel: 'Rename',
      initial: entry.name,
    );
    if (name == null || name.isEmpty || name == entry.name || !mounted) {
      return;
    }
    if (!_requireLiveConnection()) return;
    _connection?.rename(
      sftpJoin(_currentPath, entry.name),
      sftpJoin(_currentPath, name),
    );
  }

  Future<void> _delete(SftpEntry entry) async {
    final confirm =
        SettingsScope.of(context)?.sftpConfirmDelete ?? true;
    if (confirm) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete'),
          content: Text(entry.isDir
              ? 'Delete folder "${entry.name}" and its contents?'
              : 'Delete "${entry.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (!_requireLiveConnection()) return;
    final path = sftpJoin(_currentPath, entry.name);
    if (entry.isDir) {
      _connection?.deleteFolder(path);
    } else {
      _connection?.deleteFile(path);
    }
  }

  // -- Transfers ----------------------------------------------------------

  Future<void> _uploadFiles() async {
    if (!_requireLiveConnection()) return;
    if (_transferring) return;
    late final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles();
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not open the file picker.');
      return;
    }
    if (picked.isEmpty || !mounted) return;
    setState(() => _transferring = true);
    var uploaded = 0;
    var failed = 0;
    var sessionExpired = false;
    try {
      for (final file in picked) {
        final remotePath = sftpJoin(_currentPath, file.name);
        try {
          final localPath = file.path;
          if (localPath != null && localPath.isNotEmpty) {
            final local = File(localPath);
            await uploadSftpFileStreamed(
              baseUrl: widget.api.baseUrl,
              sessionToken: widget.sessionToken,
              sessionId: widget.session.sessionId,
              remotePath: remotePath,
              stream: local.openRead(),
              contentLength: await local.length(),
            );
          } else {
            final bytes = await file.readAsBytes();
            await uploadSftpFile(
              baseUrl: widget.api.baseUrl,
              sessionToken: widget.sessionToken,
              sessionId: widget.session.sessionId,
              remotePath: remotePath,
              bytes: bytes,
            );
          }
          uploaded++;
        } on SftpTransferException catch (e) {
          failed++;
          if (e.unauthorized) sessionExpired = true;
        } catch (_) {
          failed++;
        }
      }
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
    if (!mounted) return;
    if (sessionExpired) {
      widget.onSessionExpired?.call();
      return;
    }
    _showSnack(failed == 0
        ? 'Uploaded $uploaded file${uploaded == 1 ? '' : 's'}.'
        : 'Uploaded $uploaded, failed $failed.');
    _requestList(_currentPath, silent: true);
  }

  Future<void> _download(SftpEntry entry) async {
    if (_transferring || !mounted) return;
    if (!_requireLiveConnection()) return;
    final dir = await FilePicker.getDirectoryPath();
    if (dir == null || !mounted) {
      if (mounted && dir == null) _showSnack('Save canceled.');
      return;
    }
    setState(() => _transferring = true);
    try {
      final fileName =
          entry.isDir ? '${entry.name}.zip' : entry.name;
      final target = File(sftpJoin(dir, fileName));
      await downloadSftpFileTo(
        baseUrl: widget.api.baseUrl,
        sessionToken: widget.sessionToken,
        sessionId: widget.session.sessionId,
        remotePath: sftpJoin(_currentPath, entry.name),
        targetFile: target,
      );
      if (!mounted) return;
      _showSnack('Saved to ${target.path}.');
    } on SftpTransferException catch (e) {
      if (!mounted) return;
      if (e.unauthorized) {
        widget.onSessionExpired?.call();
        return;
      }
      _showSnack(e.message);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Download failed.');
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  void _onEntryAction(String action, SftpEntry entry) {
    switch (action) {
      case 'preview':
        _preview(entry);
      case 'edit':
        _editFile(entry);
      case 'download':
        _download(entry);
      case 'rename':
        _rename(entry);
      case 'delete':
        _delete(entry);
    }
  }

  /// Open a terminal on the same server (web "open in terminal").
  Future<void> _openTerminal() async {
    var dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator()),
    ).then((_) => dialogOpen = false);
    void closeDialog() {
      if (dialogOpen && context.mounted) {
        dialogOpen = false;
        Navigator.pop(context);
      }
    }

    late final RemoteSession session;
    try {
      session = await SessionOpener(
              api: widget.api, token: widget.sessionToken)
          .open(widget.session.entry, SessionKind.terminal);
    } on SessionExpiredException {
      closeDialog();
      widget.onSessionExpired?.call();
      return;
    } on NextermApiException catch (e) {
      closeDialog();
      if (mounted) _showSnack(e.message);
      return;
    } catch (_) {
      closeDialog();
      if (mounted) _showSnack('Could not open terminal.');
      return;
    }
    if (!mounted) return;
    closeDialog();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TerminalScreen(
          api: widget.api,
          sessionToken: widget.sessionToken,
          session: session,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  static const _imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
  };

  static const _maxPreviewBytes = 8 * 1024 * 1024;

  String _extensionOf(String name) {
    final idx = name.lastIndexOf('.');
    if (idx < 0 || idx == name.length - 1) return '';
    return name.substring(idx + 1).toLowerCase();
  }

  /// Preview images and text files (web FilePreviewWindow equivalent).
  Future<void> _preview(SftpEntry entry) async {
    if (entry.isDir || !mounted) return;
    final ext = _extensionOf(entry.name);
    final isImage = _imageExtensions.contains(ext);
    if (entry.size > _maxPreviewBytes) {
      _showSnack('File is too large to preview.');
      return;
    }
    setState(() => _transferring = true);
    try {
      final bytes = await downloadSftpFile(
        baseUrl: widget.api.baseUrl,
        sessionToken: widget.sessionToken,
        sessionId: widget.session.sessionId,
        remotePath: sftpJoin(_currentPath, entry.name),
      );
      if (!mounted) return;
      if (isImage) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(entry.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600)),
                ),
                Flexible(
                  child: InteractiveViewer(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                            'Could not render image.'),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        return;
      }
      String text;
      try {
        text = utf8.decode(bytes, allowMalformed: false);
      } on FormatException {
        _showSnack('Not a text file — download it instead.');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(entry.name,
              style:
                  const TextStyle(fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(ctx).size.height * 0.6,
            child: SingleChildScrollView(
              child: SelectableText(text,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on SftpTransferException catch (e) {
      if (!mounted) return;
      if (e.unauthorized) {
        widget.onSessionExpired?.call();
        return;
      }
      _showSnack(e.message);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Preview failed.');
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  /// Edit a text file (opens the remote file editor).
  void _editFile(SftpEntry entry) {
    if (entry.isDir || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RemoteFileEditorScreen(
          api: widget.api,
          sessionToken: widget.sessionToken,
          session: widget.session,
          remoteDir: _currentPath,
          entry: entry,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDate(int mtimeSeconds) {
    if (mtimeSeconds <= 0) return 'Unknown date';
    final dt = DateTime.fromMillisecondsSinceEpoch(mtimeSeconds * 1000,
            isUtc: true)
        .toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  // -- Breadcrumb ----------------------------------------------------------

  List<String> _displaySegments() {
    final all = sftpSegments(_currentPath);
    final rootSegments = sftpSegments(_rootPath);
    if (_rootPath != '/' &&
        rootSegments.length <= all.length &&
        sftpIsWithin(_currentPath, _rootPath)) {
      return all.sublist(rootSegments.length);
    }
    return all;
  }

  String _crumbTarget(int index) {
    final rootSegments = sftpSegments(_rootPath);
    final relative = _displaySegments().sublist(0, index + 1);
    if (_rootPath != '/' && sftpIsWithin(_currentPath, _rootPath)) {
      final absolute = [...rootSegments, ...relative];
      return absolute.isEmpty ? _rootPath : sftpFromSegments(absolute);
    }
    return sftpFromSegments(relative);
  }

  Widget _buildBreadcrumb() {
    final segments = _displaySegments();
    return Material(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            IconButton(
              icon: const Icon(Icons.home_outlined),
              tooltip: 'Root folder',
              onPressed: () => _navigateTo(_rootPath),
            ),
            for (var i = 0; i < segments.length; i++) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Icon(Icons.chevron_right, size: 16),
              ),
              Center(
                child: TextButton(
                  onPressed: () => _navigateTo(_crumbTarget(i)),
                  child: Text(
                    segments[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Disconnect and close',
          onPressed: _disconnectAndClose,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.session.entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _connected ? _currentPath : 'Connecting...',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.terminal),
            tooltip: 'Open terminal',
            onPressed: _connected ? _openTerminal : null,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'File actions',
            enabled: _transferring == false && _connected,
            onSelected: (value) {
              if (value == 'upload') _uploadFiles();
              if (value == 'folder') _createFolder();
              if (value == 'file') _createFile();
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                  value: 'upload', child: Text('Upload files')),
              PopupMenuItem(
                  value: 'folder', child: Text('New folder')),
              PopupMenuItem(
                  value: 'file', child: Text('New file')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.link_off),
            tooltip: 'Disconnect',
            onPressed: _disconnectAndClose,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildBreadcrumb(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search in folder',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                isDense: true,
              ),
              onChanged: (v) =>
                  setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          if (_transferring) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _buildContent(cs),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme cs) {
    if (_loading && _entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 16),
          Center(child: Text('Loading directory...')),
        ],
      );
    }
    if (_error != null && _entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 64),
          Icon(Icons.cloud_off, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => _requestList(_currentPath),
            child: const Text('Retry'),
          ),
        ],
      );
    }
    if (_entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 64),
          Icon(Icons.folder_open, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          const Text('This folder is empty.',
              textAlign: TextAlign.center),
        ],
      );
    }
    // Device preference: hide dotfiles unless enabled in Settings.
    final showHidden =
        SettingsScope.of(context)?.sftpShowHidden ?? false;
    final query = _query;
    final visible = _entries.where((e) {
      if (!showHidden && e.name.startsWith('.')) return false;
      if (query.isNotEmpty &&
          !e.name.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();
    if (visible.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 64),
          Icon(
              _query.isNotEmpty
                  ? Icons.search_off_outlined
                  : Icons.visibility_off_outlined,
              size: 56,
              color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
              _query.isNotEmpty
                  ? 'No files match "$_query".'
                  : 'Only hidden files here.',
              textAlign: TextAlign.center),
        ],
      );
    }
    final showUp = _currentPath != _rootPath;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: visible.length + (showUp ? 1 : 0),
      itemBuilder: (context, index) {
        if (showUp && index == 0) {
          return ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('..'),
            subtitle: const Text('Parent folder'),
            onTap: _goUp,
          );
        }
        final entry = visible[showUp ? index - 1 : index];
        return ListTile(
          leading: Icon(
            entry.isDir ? Icons.folder : Icons.description,
            color: entry.isDir ? cs.primary : cs.onSurfaceVariant,
          ),
          title: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: entry.isDir
              ? null
              : Text(
                  '${entry.formattedSize} • ${_formatDate(entry.mtime)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'File actions',
            onSelected: (value) => _onEntryAction(value, entry),
            itemBuilder: (ctx) => [
              if (!entry.isDir) ...[
                const PopupMenuItem(
                    value: 'preview', child: Text('Preview')),
                const PopupMenuItem(
                    value: 'edit', child: Text('Edit')),
              ],
              const PopupMenuItem(
                  value: 'download', child: Text('Download')),
              const PopupMenuItem(
                  value: 'rename', child: Text('Rename')),
              const PopupMenuItem(
                  value: 'delete', child: Text('Delete')),
            ],
          ),
          onTap: () => entry.isDir
              ? _navigateTo(sftpJoin(_currentPath, entry.name))
              : _download(entry),
        );
      },
    );
  }
}
