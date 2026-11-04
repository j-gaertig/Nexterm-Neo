part of '../sftp_renderer.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _SftpTransfers on _SftpRendererState {
  Future<void> _uploadFile([String? base, String? sheetSid]) async {
    final pickBase = base ?? _currentPath;
    final pickSid = sheetSid ?? _sessionId;
    _enterPicker();
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(allowMultiple: true);
    } catch (_) {
      result = null;
    } finally {
      _exitPicker();
      await _recoverAfterPicker();
    }
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    if (pickBase != _currentPath || pickSid != _sessionId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pickSid != _sessionId
                ? 'Session changed, please retry'
                : 'Directory changed, please retry',
          ),
        ),
      );
      _refresh();
      return;
    }
    if (_activeUploads > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload in progress, please retry shortly'),
        ),
      );
      return;
    }

    _activeUploads++;
    _setBusy(true);
    int uploaded = 0, failed = 0;
    final targetBase = _currentPath;
    final sid = _sessionId;
    final batchFiles = result.files
        .where((pickedFile) => pickedFile.path != null)
        .toList();
    if (batchFiles.isEmpty) {
      _activeUploads--;
      _setBusy(false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No files selected')));
      }
      return;
    }
    final batchPaths = <String>[];
    for (final pickedFile in batchFiles) {
      batchPaths.add(_upKey(sid, _remotePathIn(targetBase, pickedFile.name)));
    }
    _uploadingPaths.addAll(batchPaths);
    var dirChanged = false;
    var sessionChanged = false;
    final succeeded = <String>[];
    try {
      for (final pickedFile in batchFiles) {
        if (sid != _sessionId || targetBase != _currentPath) {
          dirChanged = targetBase != _currentPath;
          sessionChanged = sid != _sessionId;
          failed += batchFiles.length - uploaded - failed;
          break;
        }
        final file = File(pickedFile.path!);
        final remotePath = _remotePathIn(targetBase, pickedFile.name);
        _dropPendingFor(remotePath, sid);

        try {
          final uploadUrl = Uri.parse(
            '${ApiConfig.baseUrl}/entries/sftp/upload'
            '?sessionId=${Uri.encodeComponent(sid)}'
            '&path=${Uri.encodeComponent(remotePath)}'
            '&sessionToken=${Uri.encodeComponent(widget.token)}',
          );

          final request = http.StreamedRequest('POST', uploadUrl);
          request.headers['User-Agent'] = ApiClient.userAgent;
          request.contentLength = await file.length();
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
          if (!readFailed &&
              (response.statusCode == 200 || response.statusCode == 201)) {
            succeeded.add(remotePath);
            uploaded++;
          } else {
            failed++;
          }
        } catch (_) {
          failed++;
        }
      }
    } finally {
      for (final p in batchPaths) {
        _uploadingPaths.remove(p);
      }
      for (final remotePath in succeeded) {
        _dropPendingFor(remotePath, sid);
      }
      if (_activeUploads > 0) _activeUploads--;
      _setBusy(false);
    }

    if (mounted) {
      final msg = sessionChanged
          ? 'Session changed, upload stopped (uploaded $uploaded, failed $failed)'
          : dirChanged
          ? 'Directory changed, upload stopped (uploaded $uploaded, failed $failed)'
          : failed == 0
          ? 'Uploaded $uploaded file${uploaded != 1 ? 's' : ''}'
          : 'Uploaded $uploaded, failed $failed';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _refresh();
    }
  }

  Uri _downloadUri(String remotePath, [String? sessionId]) {
    final sid = sessionId ?? _sessionId;
    return Uri.parse(
      '${ApiConfig.baseUrl}/entries/sftp'
      '?sessionId=${Uri.encodeComponent(sid)}'
      '&path=${Uri.encodeComponent(remotePath)}'
      '&sessionToken=${Uri.encodeComponent(widget.token)}',
    );
  }

  Uri _multiDownloadUri([String? sessionId]) {
    final sid = sessionId ?? _sessionId;
    return Uri.parse(
      '${ApiConfig.baseUrl}/entries/sftp/multi'
      '?sessionId=${Uri.encodeComponent(sid)}'
      '&sessionToken=${Uri.encodeComponent(widget.token)}',
    );
  }

  String _safeFileName(String name) {
    var s = name.replaceAll(RegExp(r'[\x00-\x1F\x7F<>:"/\\|?*]'), '_').trim();
    s = s.replaceAll(RegExp(r'[. ]+$'), '');
    if (s.isEmpty ||
        s == '.' ||
        s == '..' ||
        RegExp(
          r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$',
          caseSensitive: false,
        ).hasMatch(s)) {
      s = 'download';
    }
    if (s.length > 100) {
      final dot = s.lastIndexOf('.');
      if (dot > 0 && s.length - dot <= 12) {
        s = '${s.substring(0, 100 - (s.length - dot))}${s.substring(dot)}';
      } else {
        s = s.substring(0, 100);
      }
    }
    return s;
  }

  Future<File> _streamToTemp(
    String remotePath,
    String fileName, [
    String? sessionId,
  ]) async {
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
      final safeName = _safeFileName(fileName);
      tempFile = File(
        '${tempDir.path}/nexterm_dl_${DateTime.now().microsecondsSinceEpoch}_$safeName',
      );
      final sink = tempFile.openWrite();
      try {
        await streamed.stream.pipe(sink).timeout(const Duration(minutes: 10));
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

  Future<void> _deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<File> _streamPostToTemp(
    Uri url,
    Map<String, dynamic> body,
    String fileName,
  ) async {
    final client = http.Client();
    File? tempFile;
    try {
      final request = http.Request('POST', url);
      request.headers['User-Agent'] = ApiClient.userAgent;
      request.headers['Content-Type'] = 'application/json';
      request.body = json.encode(body);
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 60));
      if (streamed.statusCode != 200) {
        throw Exception('HTTP ${streamed.statusCode}');
      }
      final tempDir = await getTemporaryDirectory();
      final safeName = _safeFileName(fileName);
      tempFile = File(
        '${tempDir.path}/nexterm_dl_${DateTime.now().microsecondsSinceEpoch}_$safeName',
      );
      final sink = tempFile.openWrite();
      try {
        await streamed.stream.pipe(sink).timeout(const Duration(minutes: 10));
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

  Future<String?> _saveTempOnce(File temp, String suggestedName) async {
    _enterPicker();
    try {
      return await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: temp.path,
          fileName: suggestedName,
        ),
      );
    } finally {
      _exitPicker();
      await _deleteQuietly(temp);
      await _recoverAfterPicker();
    }
  }

  Future<void> _showSavedLocation(String? savedValue) async {
    if (savedValue == null || savedValue.isEmpty) return;
    if (Platform.isIOS) {
      try {
        await launchUrl(
          Uri.parse('shareddocuments://'),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {}
      return;
    }
    try {
      await _SftpRendererState._revealChannel.invokeMethod(
        'showSavedDocument',
        {'value': savedValue},
      );
    } catch (_) {}
  }

  void _showDownloadedMessage(String? savedValue) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('File(s)/Folder(s) downloaded'),
        action: SnackBarAction(
          label: 'Show',
          onPressed: () => _showSavedLocation(savedValue),
        ),
      ),
    );
  }

  Future<void> _downloadSingle(
    String remotePath,
    String suggestedName,
    String base,
  ) async {
    final sid = _sessionId;
    if (!mounted) return;
    _setBusy(true);
    File? temp;
    try {
      temp = await _streamToTemp(remotePath, suggestedName, sid);
      if (!mounted || sid != _sessionId || base != _currentPath) {
        await _deleteQuietly(temp);
        temp = null;
        if (mounted && (sid != _sessionId || base != _currentPath)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                sid != _sessionId
                    ? 'Session changed, please retry'
                    : 'Directory changed, please retry',
              ),
            ),
          );
          _refresh();
        }
        return;
      }
      final saved = await _saveTempOnce(temp, suggestedName);
      temp = null;
      if (!mounted) return;
      if (saved == null) return;
      _showDownloadedMessage(saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyApiError(e, fallback: 'Download failed.')),
          ),
        );
      }
    } finally {
      await _deleteQuietly(temp);
      _setBusy(false);
    }
  }

  Future<void> _downloadFile(
    SftpEntry entry,
    String base, [
    String? sheetSid,
  ]) async {
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
    await _downloadSingle(
      _remotePathIn(base, entry.name),
      _safeFileName(entry.name),
      base,
    );
  }

  Future<void> _downloadFolder(
    SftpEntry entry,
    String base, [
    String? sheetSid,
  ]) async {
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
    await _downloadSingle(
      _remotePathIn(base, entry.name),
      '${_safeFileName(entry.name)}.zip',
      base,
    );
  }

  Future<void> _downloadMultiple(List<SftpEntry> entries) async {
    if (entries.isEmpty) return;
    final base = _currentPath;
    final sid = _sessionId;
    if (entries.length == 1) {
      final single = entries.first;
      if (single.isDir) {
        await _downloadFolder(single, base, sid);
      } else {
        await _downloadFile(single, base, sid);
      }
      return;
    }
    if (!mounted) return;
    _setBusy(true);
    File? temp;
    try {
      final paths = entries.map((e) => _remotePathIn(base, e.name)).toList();
      temp = await _streamPostToTemp(_multiDownloadUri(sid), {
        'paths': paths,
      }, 'files.zip');
      if (!mounted || sid != _sessionId || base != _currentPath) {
        await _deleteQuietly(temp);
        temp = null;
        if (mounted && (sid != _sessionId || base != _currentPath)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                sid != _sessionId
                    ? 'Session changed, please retry'
                    : 'Directory changed, please retry',
              ),
            ),
          );
          _refresh();
        }
        return;
      }
      final saved = await _saveTempOnce(temp, 'files.zip');
      temp = null;
      if (!mounted) return;
      if (saved == null) return;
      _showDownloadedMessage(saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyApiError(e, fallback: 'Download failed.')),
          ),
        );
      }
    } finally {
      await _deleteQuietly(temp);
      _setBusy(false);
    }
  }
}
