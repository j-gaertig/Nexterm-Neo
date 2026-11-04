import '../../utils/api_exception.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import '../../utils/app_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/app_ui.dart';
import '../widgets/connection_loader.dart';
import '../sftp_code_editor_screen.dart';
import 'package:http/http.dart' as http;

import '../../models/sftp_entry.dart';
import '../../services/api_config.dart';
import '../../services/connection_service.dart';
import '../../services/session_manager.dart';
import '../../utils/api_client.dart';
import '../../utils/sftp_edit.dart';
import '../../utils/sftp_settings.dart';

part 'sftp/connection.dart';
part 'sftp/dialogs.dart';
part 'sftp/transfers.dart';
part 'sftp/edit.dart';
part 'sftp/ui.dart';
part 'sftp/actions.dart';

class _SftpOps {
  static const int ready = 0x0;
  static const int listFiles = 0x1;
  static const int createFolder = 0x5;
  static const int deleteFile = 0x6;
  static const int deleteFolder = 0x7;
  static const int renameFile = 0x8;
  static const int error = 0x9;
  static const int pathSync = 0x12;
}

class _PendingEdit {
  final String sessionId;
  final String remotePath;
  final String tempPath;
  final String fileName;
  final int size;
  final int mtimeMs;
  final String hash;

  const _PendingEdit({
    required this.sessionId,
    required this.remotePath,
    required this.tempPath,
    required this.fileName,
    required this.size,
    required this.mtimeMs,
    required this.hash,
  });
}

class SftpRenderer extends StatefulWidget {
  final AppSession session;
  final String token;
  final SessionManager sessionManager;
  final SftpSettings sftpSettings;
  final VoidCallback? onDisconnected;

  const SftpRenderer({
    super.key,
    required this.session,
    required this.token,
    required this.sessionManager,
    required this.sftpSettings,
    this.onDisconnected,
  });

  @override
  State<SftpRenderer> createState() => _SftpRendererState();
}

class _SftpRendererState extends State<SftpRenderer>
    with WidgetsBindingObserver {
  static const int _maxOpenBytes = 25 * 1024 * 1024;
  static const MethodChannel _editChannel = MethodChannel('nexterm/edit');
  List<SftpEntry> _entries = [];
  String _currentPath = '/';
  String _listedPath = '/';
  String _rootPath = '/';
  List<String> _history = ['/'];
  int _historyIndex = 0;
  bool _loading = true;
  bool _connected = false;
  String? _errorMessage;
  final Set<int> _selectedIndices = {};
  bool _selectionMode = false;
  bool _uploading = false;
  bool _openingTerminal = false;
  bool _initialized = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  int _aliveResets = 0;
  static const int _maxAliveResets = 3;
  int _pickerDepth = 0;
  bool _reconnectActive = false;
  bool _quietLoop = false;
  bool _connectionLostWhilePicking = false;
  bool _quietReadyOnce = false;
  final Map<String, _PendingEdit> _pendingEdits = {};
  final Set<String> _openingPaths = {};
  final Set<String> _uploadingPaths = {};
  int _activeUploads = 0;
  int _busyCount = 0;

  String _upKey(String sessionId, String remotePath) =>
      '$sessionId|$remotePath';

  void _setBusy(bool busy) {
    if (!mounted) return;
    setState(() {
      _busyCount += busy ? 1 : -1;
      if (_busyCount < 0) _busyCount = 0;
      _uploading = _busyCount > 0;
    });
  }

  final ScrollController _scrollController = ScrollController();

  bool get _pickerOpen => _pickerDepth > 0;

  void _enterPicker() {
    _pickerDepth++;
  }

  void _exitPicker() {
    if (_pickerDepth > 0) _pickerDepth--;
  }

  bool _lastShowHiddenFiles = false;
  bool _lastSortFoldersFirst = true;

  String get _sessionId => widget.session.sessionId;

  String _normalizeRoot(String path) =>
      path == '/' || RegExp(r'^[a-z]:/$', caseSensitive: false).hasMatch(path)
      ? path
      : path.replaceFirst(RegExp(r'/$'), '');

  List<String> _pathSegments([String? path]) {
    final value = path ?? _currentPath;
    final root = _normalizeRoot(_rootPath);
    final prefix = root.endsWith('/') ? root : '$root/';
    final relative = root != '/' && (value == root || value.startsWith(prefix))
        ? value.substring(root.length).replaceFirst(RegExp(r'^/'), '')
        : value;
    return relative.split('/').where((part) => part.isNotEmpty).toList();
  }

  String _joinPath(List<String> segments) {
    final root = _normalizeRoot(_rootPath);
    if (segments.isEmpty) return root;
    if (root == '/') return '/${segments.join('/')}';
    final prefix = root.endsWith('/') ? root : '$root/';
    return '$prefix${segments.join('/')}';
  }

  String _remotePath(String name) {
    return _remotePathIn(_currentPath, name);
  }

  String _remotePathIn(String base, String name) {
    final b = base.endsWith('/') ? base : '$base/';
    return '$b$name';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.handleBack = _handleBack;
    unawaited(_sweepStaleEditTemps());
    _currentPath = widget.session.sftpPath ?? '/';
    _listedPath = _currentPath;
    _rootPath = widget.session.sftpRootPath ?? '/';
    _lastShowHiddenFiles = widget.sftpSettings.showHiddenFiles;
    _lastSortFoldersFirst = widget.sftpSettings.sortFoldersFirst;
    widget.sftpSettings.addListener(_onSftpSettingsChanged);
    _setupConnection();
  }

  String _lastRequestedPath = '/';
  double? _savedOffset;
  final Map<String, double> _scrollOffsets = {};
  final List<bool> _listBusyQueue = [];

  /// Remembers the list position of the directory that is being left so
  /// navigating back (including the system back gesture) returns to it.
  void _rememberScrollOffset(String path) {
    // The visible list can still belong to the directory that was requested
    // before this one while its listing is loading. Never attribute that
    // position to the path we are about to show.
    if (path != _listedPath || !_scrollController.hasClients) return;
    _scrollOffsets[path] = _scrollController.offset;
  }

  void _endListBusy() {
    if (_listBusyQueue.isNotEmpty) {
      _listBusyQueue.removeAt(0);
    }
  }

  bool get _showProgress =>
      _uploading || _listBusyQueue.any((counted) => counted);

  void _listDirectory(
    String path, {
    bool silent = false,
    bool keepOffset = false,
  }) {
    if (!mounted) return;
    if (widget.session.sftpChannel == null) {
      _lastRequestedPath = path;
      setState(() {
        _errorMessage = 'No SFTP channel available';
        _loading = false;
      });
      return;
    }
    _lastRequestedPath = path;
    _savedOffset = keepOffset
        ? (_scrollController.hasClients ? _scrollController.offset : null)
        : _scrollOffsets[path];
    if (_entries.isEmpty) {
      _listBusyQueue.add(false);
      if (!silent) {
        setState(() => _loading = true);
      }
    } else {
      _listBusyQueue.add(!silent);
    }
    _sendOperation(_SftpOps.listFiles, {'path': path});
  }

  void _navigateTo(String path) {
    _rememberScrollOffset(_currentPath);
    setState(() {
      _currentPath = path;
      widget.session.sftpPath = path;
      _errorMessage = null;
      _selectedIndices.clear();
      _selectionMode = false;
      if (_historyIndex < _history.length - 1) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(path);
      _historyIndex = _history.length - 1;
    });
    _listDirectory(path);
    _sendOperation(_SftpOps.pathSync, {'path': path});
  }

  bool _goBack() {
    if (_historyIndex <= 0) return false;
    _rememberScrollOffset(_currentPath);
    _historyIndex--;
    final path = _history[_historyIndex];
    setState(() {
      _currentPath = path;
      _selectedIndices.clear();
      _selectionMode = false;
    });
    widget.session.sftpPath = path;
    _listDirectory(path);
    _sendOperation(_SftpOps.pathSync, {'path': path});
    return true;
  }

  bool _handleBack() {
    // Cancel an active selection first, then walk the directory history.
    if (_selectionMode) {
      _cancelSelection();
      return true;
    }
    return _goBack();
  }

  void _goUp() {
    final parts = _pathSegments();
    if (parts.isEmpty) return;
    parts.removeLast();
    _navigateTo(_joinPath(parts));
  }

  void _onEntryTap(SftpEntry entry, int index) {
    if (_selectionMode) {
      setState(() {
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
          if (_selectedIndices.isEmpty) _selectionMode = false;
        } else {
          _selectedIndices.add(index);
        }
      });
      return;
    }
    if (entry.isDir) {
      final newPath = _remotePath(entry.name);
      _navigateTo(newPath);
    }
  }

  void _onEntryLongPress(int index) {
    setState(() {
      _selectionMode = true;
      _selectedIndices.add(index);
    });
  }

  void _refresh() =>
      _listDirectory(_currentPath, silent: true, keepOffset: true);

  void _onSftpSettingsChanged() {
    final settings = widget.sftpSettings;
    if (settings.showHiddenFiles != _lastShowHiddenFiles ||
        settings.sortFoldersFirst != _lastSortFoldersFirst) {
      _lastShowHiddenFiles = settings.showHiddenFiles;
      _lastSortFoldersFirst = settings.sortFoldersFirst;
      _refresh();
    } else if (mounted) {
      setState(() {});
    }
  }

  static const MethodChannel _revealChannel = MethodChannel(
    'nexterm/downloads',
  );

  void _cancelSelection() {
    setState(() {
      _selectedIndices.clear();
      _selectionMode = false;
    });
  }

  List<SftpEntry> _selectedEntries() {
    final entries = <SftpEntry>[];
    for (final i in _selectedIndices) {
      if (i >= 0 && i < _entries.length) {
        entries.add(_entries[i]);
      }
    }
    return entries;
  }

  void _deleteSelected() {
    _showDeleteConfirmation(_selectedEntries(), _currentPath, _sessionId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _flushPendingUploads();
    }
  }

  @override
  void didUpdateWidget(SftpRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      if (oldWidget.session.handleBack == _handleBack) {
        oldWidget.session.handleBack = null;
      }
      widget.session.handleBack = _handleBack;
    }
    if (oldWidget.session.sessionId != widget.session.sessionId) {
      final oldSid = oldWidget.session.sessionId;
      for (final key in _pendingEdits.keys.toList()) {
        final current = _pendingEdits[key];
        if (current == null || current.sessionId != oldSid) {
          continue;
        }
        if (_uploadingPaths.contains(key)) {
          continue;
        }
        final pending = _pendingEdits.remove(key);
        if (pending != null) {
          unawaited(_deleteQuietly(File(pending.tempPath)));
        }
      }
      _openingPaths.removeWhere((k) => k.startsWith('$oldSid|'));
      _uploadingPaths.removeWhere((k) => k.startsWith('$oldSid|'));
      _entries = [];
      _currentPath = widget.session.sftpPath ?? '/';
      _listedPath = _currentPath;
      _rootPath = widget.session.sftpRootPath ?? '/';
      _lastRequestedPath = _currentPath;
      _savedOffset = null;
      _scrollOffsets.clear();
      _listBusyQueue.clear();
      _history = [_currentPath];
      _historyIndex = 0;
      _selectedIndices.clear();
      _selectionMode = false;
      _loading = true;
      _errorMessage = null;
      _connected = false;
      _reconnectAttempts = 0;
      _aliveResets = 0;
      _connectionLostWhilePicking = false;
      _quietReadyOnce = false;
      _initialized = false;
      if (!identical(oldWidget.session, widget.session)) {
        try {
          oldWidget.session.sftpSubscription?.cancel();
        } catch (_) {}
        oldWidget.session.sftpSubscription = null;
      }
      _setupConnection();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      widget.session.sftpSubscription?.cancel();
    } catch (_) {}
    widget.session.sftpSubscription = null;
    for (final key in _pendingEdits.keys.toList()) {
      if (_uploadingPaths.contains(key)) {
        continue;
      }
      final pending = _pendingEdits.remove(key);
      if (pending != null) {
        unawaited(_deleteQuietly(File(pending.tempPath)));
      }
    }
    _openingPaths.clear();
    _scrollController.dispose();
    widget.sftpSettings.removeListener(_onSftpSettingsChanged);
    if (widget.session.handleBack == _handleBack) {
      widget.session.handleBack = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _selectionMode
              ? _buildWithSelectionBar()
              : _buildMainContent(),
        ),
        if (!_selectionMode && _connected)
          Positioned(
            right: 16,
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
            child: FloatingActionButton(
              onPressed: _showAddMenu,
              tooltip: 'Add files',
              child: Icon(AppIcons.plus),
            ),
          ),
      ],
    );
  }
}
