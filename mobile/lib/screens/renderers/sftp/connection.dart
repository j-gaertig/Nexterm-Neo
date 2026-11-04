part of '../sftp_renderer.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _SftpConnection on _SftpRendererState {
  void _setupConnection() {
    if (_initialized) return;
    _initialized = true;

    final channel = widget.session.sftpChannel;
    if (channel == null) {
      setState(() {
        _errorMessage = 'No SFTP channel available';
        _loading = false;
        _connected = false;
        _listBusyQueue.clear();
      });
      return;
    }

    if (widget.session.sftpSubscription == null) {
      widget.session.sftpSubscription = channel.stream.listen(
        _processMessage,
        onError: (error) {
          if (_pickerOpen) {
            _connectionLostWhilePicking = true;
            _listBusyQueue.clear();
            if (mounted) {
              setState(() {});
            }
            return;
          }
          if (mounted) {
            setState(() {
              _errorMessage = 'Connection lost. Reconnecting may help.';
              _connected = false;
              _listBusyQueue.clear();
            });
          }
          widget.session.isConnected = false;
          _attemptReconnect();
        },
        onDone: () {
          if (_pickerOpen) {
            _connectionLostWhilePicking = true;
            _listBusyQueue.clear();
            if (mounted) {
              setState(() {});
            }
            return;
          }
          if (mounted) {
            setState(() {
              _connected = false;
              _listBusyQueue.clear();
            });
          }
          widget.session.isConnected = false;
          _attemptReconnect();
        },
      );
    } else {
      _connected = widget.session.isConnected;
      if (_connected) {
        _listDirectory(_currentPath, keepOffset: true);
      } else {
        _attemptReconnect();
      }
    }
  }

  Future<void> _attemptReconnect({bool quiet = false}) async {
    if (_reconnectActive) return;
    _quietLoop = quiet;
    _reconnectActive = true;
    try {
      while (mounted) {
        try {
          if (_pickerOpen) {
            _connectionLostWhilePicking = true;
            _quietReadyOnce = false;
            return;
          }
          if (_reconnectAttempts >= _SftpRendererState._maxReconnectAttempts) {
            final alive = await _serverSessionAlive();
            if (!mounted) return;
            if (_pickerOpen) {
              _connectionLostWhilePicking = true;
              _quietReadyOnce = false;
              return;
            }
            if (alive && _aliveResets < _SftpRendererState._maxAliveResets) {
              _aliveResets++;
              _reconnectAttempts = 0;
            } else {
              _quietReadyOnce = false;
              widget.onDisconnected?.call();
              return;
            }
          }
          _reconnectAttempts++;
          final delay = Duration(seconds: _reconnectAttempts.clamp(1, 5));
          await Future.delayed(delay);
          if (!mounted) return;
          if (_pickerOpen) {
            _connectionLostWhilePicking = true;
            _quietReadyOnce = false;
            return;
          }
          if (await _reconnectNow()) return;
        } catch (_) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    } catch (_) {
    } finally {
      _reconnectActive = false;
      _quietLoop = false;
    }
  }

  Future<bool> _reconnectNow() async {
    final quiet = _quietLoop;
    final success = await widget.sessionManager.reconnectSftpSession(
      token: widget.token,
      session: widget.session,
    );
    if (!mounted || !success) return false;
    _quietReadyOnce = quiet;
    _reconnectAttempts = 0;
    _aliveResets = 0;
    _initialized = false;
    try {
      await widget.session.sftpSubscription?.cancel();
    } catch (_) {}
    widget.session.sftpSubscription = null;
    setState(() {
      _errorMessage = null;
    });
    _setupConnection();
    return true;
  }

  Future<bool> _serverSessionAlive() async {
    try {
      final sessions = await ConnectionService.listSessions(
        token: widget.token,
      ).timeout(const Duration(seconds: 10));
      return sessions.any((s) => s['sessionId'] == _sessionId);
    } catch (_) {
      return true;
    }
  }

  Future<void> _recoverAfterPicker() async {
    if (!mounted || _pickerOpen) return;
    if (!_connectionLostWhilePicking) return;
    _connectionLostWhilePicking = false;
    _attemptReconnect(quiet: true);
  }

  void _processMessage(dynamic data) {
    Uint8List bytes;
    if (data is Uint8List) {
      bytes = data;
    } else if (data is List<int>) {
      bytes = Uint8List.fromList(data);
    } else if (data is String) {
      bytes = Uint8List.fromList(utf8.encode(data));
    } else {
      return;
    }
    if (bytes.isEmpty) return;

    final operation = bytes[0];
    String jsonPayload = '';
    if (bytes.length > 1) {
      try {
        jsonPayload = utf8.decode(bytes.sublist(1));
      } catch (_) {
        return;
      }
    }

    switch (operation) {
      case _SftpOps.ready:
        Map<String, dynamic> ready = {};
        try {
          ready = json.decode(jsonPayload) as Map<String, dynamic>;
        } catch (_) {}
        final readyRoot = ready['rootPath'] is String
            ? ready['rootPath'] as String
            : '/';
        final readyPath = ready['path'] is String
            ? ready['path'] as String
            : readyRoot;
        final samePath = !mounted || readyPath == _currentPath;
        final quiet = _quietReadyOnce;
        _quietReadyOnce = false;
        if (mounted) {
          final newRoot = readyRoot;
          final initialPath = readyPath;
          setState(() {
            _connected = true;
            _errorMessage = null;
            _rootPath = newRoot;
            _currentPath = initialPath;
            widget.session.sftpPath = initialPath;
            widget.session.sftpRootPath = _rootPath;
            if (!quiet || !samePath) {
              _history = [initialPath];
              _historyIndex = 0;
            }
            _selectedIndices.clear();
            _selectionMode = false;
          });
        }
        widget.session.isConnected = true;
        _reconnectAttempts = 0;
        _listDirectory(readyPath, silent: quiet, keepOffset: samePath);
        break;
      case _SftpOps.listFiles:
        _handleDirectoryListed(jsonPayload);
        break;
      case _SftpOps.error:
        var listFailed = _listBusyQueue.isNotEmpty;
        try {
          final decoded = json.decode(jsonPayload);
          if (decoded is Map<String, dynamic> && decoded.containsKey('op')) {
            listFailed = (decoded['op'] as num?)?.toInt() == _SftpOps.listFiles;
          }
          if (mounted) {
            setState(() {
              _errorMessage = decoded is Map<String, dynamic>
                  ? decoded['message'] ?? 'Unknown error'
                  : 'Unknown error';
              if (listFailed) {
                _loading = false;
              }
            });
          }
        } catch (_) {
          listFailed = _listBusyQueue.isNotEmpty;
          if (mounted) {
            setState(() {
              _errorMessage = jsonPayload.isNotEmpty
                  ? jsonPayload
                  : 'Unknown error';
              if (listFailed) {
                _loading = false;
              }
            });
          }
        }
        if (listFailed) {
          _endListBusy();
        }
        break;
      case _SftpOps.pathSync:
        try {
          final payload = json.decode(jsonPayload) as Map<String, dynamic>;
          final path = payload['path'] as String?;
          if (path != null && path != _currentPath && mounted) {
            _rememberScrollOffset(_currentPath);
            setState(() {
              _currentPath = path;
              widget.session.sftpPath = path;
              _history = [..._history.take(_historyIndex + 1), path];
              _historyIndex = _history.length - 1;
              _selectedIndices.clear();
              _selectionMode = false;
            });
            _listDirectory(path);
          }
        } catch (_) {}
        break;
      default:
        _listDirectory(_currentPath, silent: true);
        break;
    }
  }

  void _handleDirectoryListed(String jsonPayload) {
    if (!mounted) return;
    if (_currentPath != _lastRequestedPath) {
      _endListBusy();
      return;
    }
    try {
      final decoded = json.decode(jsonPayload);
      if (decoded is Map<String, dynamic>) {
        final echoed = decoded['path'];
        if (echoed is String && echoed.isNotEmpty && echoed != _currentPath) {
          _endListBusy();
          return;
        }
        final message = decoded['message'] ?? decoded['error'];
        if (message is String && message.isNotEmpty) {
          setState(() {
            _errorMessage = message;
            _loading = false;
          });
          _endListBusy();
          return;
        }
        if (!decoded.containsKey('files') &&
            (decoded.containsKey('message') || decoded.containsKey('error'))) {
          setState(() {
            _errorMessage = 'Failed to load directory';
            _loading = false;
          });
          _endListBusy();
          return;
        }
      }
      final List<dynamic> files = decoded is List
          ? decoded
          : (decoded['files'] ?? []);
      var entries = files
          .map((e) => SftpEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      if (!widget.sftpSettings.showHiddenFiles) {
        entries = entries.where((e) => !e.name.startsWith('.')).toList();
      }

      entries.sort((a, b) {
        if (widget.sftpSettings.sortFoldersFirst) {
          if (a.isDir && !b.isDir) return -1;
          if (!a.isDir && b.isDir) return 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      setState(() {
        _entries = entries;
        _listedPath = _currentPath;
        _loading = false;
        _errorMessage = null;
        _selectedIndices.clear();
        _selectionMode = false;
      });
      _endListBusy();
      if (_savedOffset != null) {
        final target = _savedOffset!;
        _savedOffset = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          final max = _scrollController.position.maxScrollExtent;
          if (max <= 0) return;
          _scrollController.jumpTo(target.clamp(0.0, max).toDouble());
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not read the directory listing.';
        _loading = false;
      });
      _endListBusy();
    }
  }

  void _sendOperation(int operation, Map<String, dynamic> payload) {
    final channel = widget.session.sftpChannel;
    if (channel == null) return;
    try {
      final jsonStr = json.encode(payload);
      final jsonBytes = utf8.encode(jsonStr);
      final message = Uint8List(1 + jsonBytes.length);
      message[0] = operation;
      message.setRange(1, message.length, jsonBytes);
      channel.sink.add(message);
    } catch (_) {}
  }
}
