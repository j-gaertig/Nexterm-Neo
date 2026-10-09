import 'package:flutter/material.dart';

import '../../api/nexterm_api.dart';
import '../../servers/server_models.dart';

/// Per-server notes (web NotesRenderer equivalent): `config.notes` +
/// `config.showNoteInList` on the entry detail, saved via
/// `PATCH /api/entries/:id` with the merged config.
class ServerNotesScreen extends StatefulWidget {
  const ServerNotesScreen(
      {super.key,
      required this.api,
      required this.token,
      required this.entry,
      this.onSessionExpired});

  final NextermApi api;
  final String token;
  final ServerEntry entry;
  final VoidCallback? onSessionExpired;

  @override
  State<ServerNotesScreen> createState() => _ServerNotesScreenState();
}

class _ServerNotesScreenState extends State<ServerNotesScreen> {
  final _notes = TextEditingController();
  bool _showInList = false;
  Map<String, dynamic>? _baseConfig;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.api
          .fetchEntry(widget.token, widget.entry.id);
      if (!mounted) return;
      Map<String, dynamic> cfg = const {};
      final config = detail['config'];
      if (config is Map) cfg = Map<String, dynamic>.from(config);
      setState(() {
        _baseConfig = cfg;
        _notes.text = cfg['notes'] as String? ?? '';
        _showInList = cfg['showNoteInList'] == true;
        _loading = false;
      });
    } on SessionExpiredException {
      if (!mounted) return;
      widget.onSessionExpired?.call();
      return;
    } on NextermApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load notes.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final base = _baseConfig;
    if (base == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final config = Map<String, dynamic>.from(base)
        ..['notes'] = _notes.text
        ..['showNoteInList'] = _showInList;
      await widget.api.updateEntry(
          widget.token, widget.entry.id, {'config': config});
      if (!mounted) return;
      Navigator.pop(context, true);
    } on SessionExpiredException {
      widget.onSessionExpired?.call();
    } on NextermApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not save notes.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notes · ${widget.entry.name}'),
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
                      onPressed: _save,
                      child: const Text('Save'),
                    ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _baseConfig == null
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
              : ListView(
                  padding:
                      const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show in server list',
                          style: TextStyle(
                              fontWeight: FontWeight.w600)),
                      subtitle: const Text(
                          'Display a note badge on the server row',
                          style: TextStyle(fontSize: 12)),
                      value: _showInList,
                      onChanged: (v) =>
                          setState(() => _showInList = v),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notes,
                      maxLines: null,
                      minLines: 10,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .error)),
                    ],
                  ],
                ),
    );
  }
}
