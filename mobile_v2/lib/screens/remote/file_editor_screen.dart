import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:nexterm_v2/api/nexterm_api.dart';
import 'package:nexterm_v2/remote/session_opener.dart';

import 'sftp_protocol.dart';
import 'sftp_service.dart';

/// Remote text file editor (web FileEditorWindow equivalent): download,
/// edit, upload back. Text files up to 1 MB.
class RemoteFileEditorScreen extends StatefulWidget {
  const RemoteFileEditorScreen(
      {super.key,
      required this.api,
      required this.sessionToken,
      required this.session,
      required this.remoteDir,
      required this.entry,
      this.onSessionExpired});

  final NextermApi api;
  final String sessionToken;
  final RemoteSession session;
  final String remoteDir;
  final SftpEntry entry;
  final VoidCallback? onSessionExpired;

  @override
  State<RemoteFileEditorScreen> createState() =>
      _RemoteFileEditorScreenState();
}

class _RemoteFileEditorScreenState
    extends State<RemoteFileEditorScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  static const _maxBytes = 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (!_dirty && mounted) setState(() => _dirty = true);
    });
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _remotePath =>
      sftpJoin(widget.remoteDir, widget.entry.name);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.entry.size > _maxBytes) {
        throw const SftpTransferException(
            'File is too large to edit (1 MB limit).');
      }
      final bytes = await downloadSftpFile(
        baseUrl: widget.api.baseUrl,
        sessionToken: widget.sessionToken,
        sessionId: widget.session.sessionId,
        remotePath: _remotePath,
      );
      final text = utf8.decode(bytes, allowMalformed: false);
      if (!mounted) return;
      setState(() {
        _controller.text = text;
        _dirty = false;
        _loading = false;
      });
    } on SftpTransferException catch (e) {
      if (!mounted) return;
      if (e.unauthorized) {
        setState(() => _loading = false);
        widget.onSessionExpired?.call();
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _error = 'Not a text file.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load file.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await uploadSftpFile(
        baseUrl: widget.api.baseUrl,
        sessionToken: widget.sessionToken,
        sessionId: widget.session.sessionId,
        remotePath: _remotePath,
        bytes: Uint8List.fromList(utf8.encode(_controller.text)),
      );
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File saved.')),
      );
    } on SftpTransferException catch (e) {
      if (!mounted) return;
      if (e.unauthorized) {
        setState(() => _saving = false);
        widget.onSessionExpired?.call();
        return;
      }
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Save failed.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _saving
                  ? const Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2)))
                  : FilledButton.tonal(
                      onPressed: _dirty ? _save : null,
                      child: const Text('Save'),
                    ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _controller.text.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _load,
                            child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : Padding(
                  padding:
                      const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[
                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .errorContainer,
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                  fontSize: 12)),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          maxLines: null,
                          expands: true,
                          textAlignVertical:
                              TextAlignVertical.top,
                          keyboardType:
                              TextInputType.multiline,
                          style: const TextStyle(
                              fontFamily: 'monospace'),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding:
                                EdgeInsets.all(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
