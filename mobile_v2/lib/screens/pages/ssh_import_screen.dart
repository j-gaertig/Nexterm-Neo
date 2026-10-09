import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../api/nexterm_api.dart';
import '../../servers/folder_picker.dart';
import '../../servers/server_models.dart';
import '../../servers/ssh_import.dart';

/// Import `~/.ssh/config` hosts (web SSHConfigImportDialog
/// equivalent): pick/paste the file, review parsed hosts, choose a
/// target folder, import. Key-file upload is desktop-only and skipped
/// — link identities afterwards in the editor.
class SshImportScreen extends StatefulWidget {
  const SshImportScreen(
      {super.key,
      required this.api,
      required this.token,
      this.onSessionExpired});

  final NextermApi api;
  final String token;
  final VoidCallback? onSessionExpired;

  @override
  State<SshImportScreen> createState() => _SshImportScreenState();
}

class _SshImportScreenState extends State<SshImportScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _hosts = [];
  String? _error;
  bool _importing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reparse() {
    setState(() {
      _error = null;
      try {
        _hosts = parseSshConfig(_controller.text);
      } catch (_) {
        _hosts = const [];
        _error = 'Could not parse the config.';
      }
    });
  }

  Future<void> _pickFile() async {
    List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not open the file picker.')),
      );
      return;
    }
    if (picked.isEmpty || !mounted) return;
    try {
      final bytes = await picked.first.readAsBytes();
      final text = String.fromCharCodes(bytes);
      if (!mounted) return;
      setState(() => _controller.text = text);
      _reparse();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read file.')),
      );
    }
  }

  Future<void> _import() async {
    if (_hosts.isEmpty || !mounted) return;
    List<EntryNode>? nodes;
    try {
      final tree = await widget.api.fetchEntries(widget.token);
      nodes = parseEntryTree(tree);
    } on SessionExpiredException {
      widget.onSessionExpired?.call();
      return;
    } catch (_) {
      nodes = null;
    }
    if (!mounted) return;
    final pick = nodes == null
        ? const FolderPick(null)
        : await showFolderPicker(context, nodes,
            title: 'Import into folder');
    if (pick == null || !mounted) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final result = await widget.api.importSshConfig(
        widget.token,
        {
          'servers': _hosts,
          if (pick.folderId != null)
            'folderId': pick.folderId,
        },
      );
      if (!mounted) return;
      setState(() => _importing = false);
      final message = result['message'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(message is String
                ? message
                : 'Import finished.')),
      );
      Navigator.pop(context, true);
    } on SessionExpiredException {
      widget.onSessionExpired?.call();
    } on NextermApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _importing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Import failed.';
        _importing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Import SSH config')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Paste your ~/.ssh/config or pick the file.',
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.upload_file,
                      size: 18),
                  label: const Text('Pick file'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              maxLines: 6,
              minLines: 3,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'Host example\n  HostName 192.168.1.10\n  User root',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _reparse(),
            ),
          ),
          if (_error != null)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(_error!,
                  style: TextStyle(
                      color: cs.error, fontSize: 12)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              _hosts.isEmpty
                  ? 'No hosts found.'
                  : '${_hosts.length} host${_hosts.length == 1 ? '' : 's'} found:',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _hosts.length,
              itemBuilder: (_, i) {
                final host = _hosts[i];
                return Card(
                  elevation: 0,
                  color: cs.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(12)),
                  child: ListTile(
                    dense: true,
                    leading:
                        const Icon(Icons.dns_outlined),
                    title: Text('${host['name']}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${host['ip']}:${host['port']}',
                        style: const TextStyle(
                            fontSize: 12)),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: FilledButton(
                onPressed: (_hosts.isEmpty || _importing)
                    ? null
                    : _import,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16)),
                child: _importing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2))
                    : Text(
                        'Import ${_hosts.length} host${_hosts.length == 1 ? '' : 's'}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
