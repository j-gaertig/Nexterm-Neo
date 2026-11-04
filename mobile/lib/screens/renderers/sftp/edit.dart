part of '../sftp_renderer.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _SftpExternalEdit on _SftpRendererState {
  bool _hasPendingFor(String remotePath, [String? sessionId]) {
    final full = _upKey(sessionId ?? _sessionId, remotePath);
    final prefix = full.endsWith('/') ? full : '$full/';
    for (final key in _pendingEdits.keys) {
      if (key == full || key.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  bool _hasUploadingFor(String remotePath, [String? sessionId]) {
    final sid = sessionId ?? _sessionId;
    final full = _upKey(sid, remotePath);
    if (_uploadingPaths.contains(full)) {
      return true;
    }
    final childPrefix = full.endsWith('/') ? full : '$full/';
    for (final key in _uploadingPaths) {
      if (key.startsWith(childPrefix)) {
        return true;
      }
    }
    return false;
  }

  void _dropPendingFor(String remotePath, [String? sessionId]) {
    final full = _upKey(sessionId ?? _sessionId, remotePath);
    final prefix = full.endsWith('/') ? full : '$full/';
    for (final key in _pendingEdits.keys.toList()) {
      if (key == full || key.startsWith(prefix)) {
        final stale = _pendingEdits[key];
        if (stale != null &&
            _uploadingPaths.contains(
              _upKey(stale.sessionId, stale.remotePath),
            )) {
          continue;
        }
        _pendingEdits.remove(key);
        if (stale != null) {
          unawaited(_deleteQuietly(File(stale.tempPath)));
        }
      }
    }
  }

  void _dropAllPendingEdits(String sessionId) {
    for (final key in _pendingEdits.keys.toList()) {
      final stale = _pendingEdits[key];
      if (stale == null || stale.sessionId != sessionId) {
        continue;
      }
      if (_uploadingPaths.contains(key)) {
        continue;
      }
      _pendingEdits.remove(key);
      unawaited(_deleteQuietly(File(stale.tempPath)));
    }
  }

  Future<bool> _confirmDiscardOpenEdits() async {
    if (!widget.sftpSettings.warnBeforeDiscardEdit) return true;
    if (!mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard open file?'),
        content: const Text(
          'The open file may contain unsaved changes that will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  Future<_PendingEdit?> _snapshotEdit(
    File file,
    String remotePath,
    String fileName,
    String sessionId,
  ) async {
    try {
      final stat = await file.stat();
      final hash = await hashEditFile(file);
      return _PendingEdit(
        sessionId: sessionId,
        remotePath: remotePath,
        tempPath: file.path,
        fileName: fileName,
        size: stat.size,
        mtimeMs: stat.modified.millisecondsSinceEpoch,
        hash: hash,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _editChanged(_PendingEdit pending) async {
    try {
      final file = File(pending.tempPath);
      if (!await file.exists()) return false;
      final stat = await file.stat();
      final hash = await hashEditFile(file);
      return pendingEditChanged(
        oldSize: pending.size,
        oldMtimeMs: pending.mtimeMs,
        oldHash: pending.hash,
        newSize: stat.size,
        newMtimeMs: stat.modified.millisecondsSinceEpoch,
        newHash: hash,
      );
    } catch (_) {
      try {
        if (!await File(pending.tempPath).exists()) return false;
      } catch (_) {}
      return true;
    }
  }

  Future<File> _streamToEditTemp(
    String remotePath,
    String fileName,
    String sessionId,
  ) async {
    final client = http.Client();
    File? tempFile;
    try {
      final request = http.Request('GET', _downloadUri(remotePath, sessionId));
      request.headers['User-Agent'] = ApiClient.userAgent;
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 60));
      if (streamed.statusCode != 200) {
        throw Exception('HTTP ${streamed.statusCode}');
      }
      final tempDir = await getTemporaryDirectory();
      final editDir = Directory('${tempDir.path}/nexterm_edit/$sessionId');
      await editDir.create(recursive: true);
      final safeName = _safeFileName(fileName);
      tempFile = File(
        '${editDir.path}/${DateTime.now().microsecondsSinceEpoch}_$safeName',
      );
      final sink = tempFile.openWrite();
      try {
        var received = 0;
        await streamed.stream
            .map((chunk) {
              received += chunk.length;
              if (received > _SftpRendererState._maxOpenBytes) {
                throw Exception('File is too large to open');
              }
              return chunk;
            })
            .pipe(sink)
            .timeout(const Duration(minutes: 10));
      } catch (_) {
        try {
          await sink.close();
        } catch (_) {}
        await _deleteQuietly(tempFile);
        tempFile = null;
        rethrow;
      }
      return tempFile;
    } catch (_) {
      await _deleteQuietly(tempFile);
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<void> _sweepStaleEditTemps() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final editRoot = Directory('${tempDir.path}/nexterm_edit');
      if (!await editRoot.exists()) return;
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      await for (final entity in editRoot.list(recursive: true)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              await entity.delete();
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<bool> _invokeNativeOpen(String tempPath) async {
    try {
      final result = await _SftpRendererState._editChannel.invokeMethod<bool>(
        'open',
        {'path': tempPath},
      );
      return result ?? true;
    } on MissingPluginException catch (_) {
      return false;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openEntry(
    SftpEntry entry,
    String base, [
    String? sheetSid,
  ]) async {
    if (entry.isDir) return;
    final actionSid = sheetSid ?? _sessionId;
    if (actionSid != _sessionId) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session changed, please retry')),
      );
      _refresh();
      return;
    }
    if (base != _currentPath) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Directory changed, please retry')),
      );
      _refresh();
      return;
    }
    if (entry.size > _SftpRendererState._maxOpenBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File is too large to open')),
      );
      return;
    }
    final remotePath = _remotePathIn(base, entry.name);
    final fileName = _safeFileName(entry.name);
    final openSessionId = _sessionId;
    final pkey = _upKey(openSessionId, remotePath);
    if (!mounted || _openingPaths.contains(pkey)) return;
    if (_uploadingPaths.contains(_upKey(openSessionId, remotePath))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload in progress, please retry shortly'),
        ),
      );
      return;
    }
    _openingPaths.add(pkey);
    _setBusy(true);
    File? temp;
    _PendingEdit? snapshot;
    try {
      temp = await _streamToEditTemp(remotePath, fileName, openSessionId);
      if (!mounted || openSessionId != _sessionId || base != _currentPath) {
        await _deleteQuietly(temp);
        temp = null;
        if (mounted && (openSessionId != _sessionId || base != _currentPath)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                openSessionId != _sessionId
                    ? 'Session changed, please retry'
                    : 'Directory changed, please retry',
              ),
            ),
          );
          _refresh();
        }
        return;
      }
      snapshot = await _snapshotEdit(temp, remotePath, fileName, openSessionId);
      if (!mounted || openSessionId != _sessionId) {
        await _deleteQuietly(temp);
        temp = null;
        return;
      }
      if (snapshot == null) {
        await _deleteQuietly(temp);
        temp = null;
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Open failed')));
        }
        return;
      }
      if (_uploadingPaths.contains(_upKey(openSessionId, remotePath))) {
        await _deleteQuietly(temp);
        temp = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Upload in progress, please retry shortly'),
            ),
          );
        }
        return;
      }
      if (_pendingEdits.isNotEmpty) {
        final proceed = await _confirmDiscardOpenEdits();
        if (!mounted ||
            openSessionId != _sessionId ||
            base != _currentPath ||
            _uploadingPaths.contains(_upKey(openSessionId, remotePath))) {
          await _deleteQuietly(temp);
          temp = null;
          return;
        }
        if (!proceed) {
          await _deleteQuietly(temp);
          temp = null;
          return;
        }
        _dropAllPendingEdits(openSessionId);
      }
      _dropPendingFor(remotePath, openSessionId);
      _pendingEdits[pkey] = snapshot;
      _enterPicker();
      bool opened = false;
      try {
        opened = await _invokeNativeOpen(temp.path);
      } finally {
        _exitPicker();
        await _recoverAfterPicker();
      }
      if (!mounted) {
        if (opened) {
          temp = null;
        } else if (identical(_pendingEdits[pkey], snapshot)) {
          _pendingEdits.remove(pkey);
        }
        return;
      }
      if (!opened) {
        final saved = await _saveTempOnce(temp, fileName);
        temp = null;
        if (identical(_pendingEdits[pkey], snapshot)) {
          _pendingEdits.remove(pkey);
        }
        if (saved == null) return;
        _showDownloadedMessage(saved);
        return;
      }
      temp = null;
      await _flushPendingUpload(pkey);
    } catch (e) {
      await _deleteQuietly(temp);
      if (snapshot != null && identical(_pendingEdits[pkey], snapshot)) {
        try {
          if (!await File(snapshot.tempPath).exists()) {
            _pendingEdits.remove(pkey);
          }
        } catch (_) {}
      }
      if (snapshot != null && !identical(_pendingEdits[pkey], snapshot)) {
        await _deleteQuietly(File(snapshot.tempPath));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyApiError(e, fallback: 'Open failed.')),
          ),
        );
      }
    } finally {
      _openingPaths.remove(pkey);
      await _deleteQuietly(temp);
      _setBusy(false);
    }
  }

  Future<void> _flushPendingUploads() async {
    if (!mounted || _pendingEdits.isEmpty) return;
    for (final key in _pendingEdits.keys.toList()) {
      await _flushPendingUpload(key);
    }
  }

  Future<void> _flushPendingUpload(String pkey) async {
    final pending = _pendingEdits[pkey];
    if (pending == null || !mounted) return;
    if (_uploadingPaths.contains(pkey)) return;
    if (pending.sessionId != _sessionId) {
      if (identical(_pendingEdits[pkey], pending)) {
        _pendingEdits.remove(pkey);
      }
      await _deleteQuietly(File(pending.tempPath));
      return;
    }
    if (!await File(pending.tempPath).exists()) {
      if (identical(_pendingEdits[pkey], pending)) {
        _pendingEdits.remove(pkey);
      }
      return;
    }
    final changed = await _editChanged(pending);
    if (!changed || !mounted) return;
    if (!identical(_pendingEdits[pkey], pending)) return;
    await _uploadEditedFile(pending);
  }

  Future<void> _uploadEditedFile(_PendingEdit pending) async {
    final file = File(pending.tempPath);
    final pkey = _upKey(pending.sessionId, pending.remotePath);
    final remotePath = pending.remotePath;
    if (!mounted) {
      if (identical(_pendingEdits[pkey], pending)) {
        _pendingEdits.remove(pkey);
      }
      await _deleteQuietly(file);
      return;
    }
    final sid = pending.sessionId;
    if (sid != _sessionId) {
      if (identical(_pendingEdits[pkey], pending)) {
        _pendingEdits.remove(pkey);
      }
      await _deleteQuietly(file);
      return;
    }
    if (_uploadingPaths.contains(pkey)) {
      return;
    }
    if (_activeUploads > 0) {
      return;
    }
    _activeUploads++;
    _setBusy(true);
    _uploadingPaths.add(pkey);
    try {
      final editedSize = await file.length();
      if (editedSize > _SftpRendererState._maxOpenBytes) {
        return;
      }
      final uploadUrl = Uri.parse(
        '${ApiConfig.baseUrl}/entries/sftp/upload'
        '?sessionId=${Uri.encodeComponent(sid)}'
        '&path=${Uri.encodeComponent(remotePath)}'
        '&sessionToken=${Uri.encodeComponent(widget.token)}',
      );
      final request = http.StreamedRequest('POST', uploadUrl);
      request.headers['User-Agent'] = ApiClient.userAgent;
      request.contentLength = editedSize;
      var readFailed = false;
      file.openRead().listen(
        request.sink.add,
        onDone: request.sink.close,
        onError: (e) {
          readFailed = true;
          request.sink.close();
        },
      );
      final response = await request.send().timeout(
        const Duration(minutes: 10),
      );
      await response.stream.drain();
      if (!mounted) {
        if (identical(_pendingEdits[pkey], pending)) {
          _pendingEdits.remove(pkey);
        }
        await _deleteQuietly(file);
        return;
      }
      if (sid != _sessionId) {
        if (identical(_pendingEdits[pkey], pending)) {
          _pendingEdits.remove(pkey);
        }
        await _deleteQuietly(file);
        return;
      }
      if (!identical(_pendingEdits[pkey], pending)) {
        await _deleteQuietly(file);
        return;
      }
      if (!readFailed &&
          (response.statusCode == 200 || response.statusCode == 201)) {
        _pendingEdits.remove(pkey);
        await _deleteQuietly(file);
        _refresh();
      }
    } catch (_) {
    } finally {
      _uploadingPaths.remove(pkey);
      if (_activeUploads > 0) _activeUploads--;
      _setBusy(false);
    }
  }
}
