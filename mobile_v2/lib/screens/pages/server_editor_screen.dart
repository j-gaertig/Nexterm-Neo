import 'package:flutter/material.dart';

import '../../api/nexterm_api.dart';
import '../../servers/identity.dart';

/// Create/edit payload for `PUT/PATCH /api/entries[/:id]`
/// (see `server/validations/server.js`).
///
/// [baseConfig] is the stored config of an edited entry: edits merge into
/// it so untouched keys (MAC/WOL, monitoring, hooks, ...) survive —
/// the server replaces `config` wholesale on update.
Map<String, dynamic> buildEntryPayload({
  required String name,
  required String protocol,
  required String ip,
  int? port,
  List<int> identities = const [],
  Map<String, dynamic>? baseConfig,
}) {
  final config = <String, dynamic>{...?baseConfig};
  config['protocol'] = protocol;
  config['ip'] = ip;
  final p = port;
  if (p != null) {
    config['port'] = p;
  } else {
    config.remove('port');
  }
  return {
    'name': name,
    'type': 'server',
    'config': config,
    'identities': identities,
  };
}

/// Create (`entryId == null`) or edit a server entry.
class ServerEditorScreen extends StatefulWidget {
  const ServerEditorScreen(
      {super.key,
      required this.api,
      required this.token,
      this.entryId});

  final NextermApi api;
  final String token;
  final int? entryId;

  @override
  State<ServerEditorScreen> createState() => _ServerEditorScreenState();
}

class _ServerEditorScreenState extends State<ServerEditorScreen> {
  final _name = TextEditingController();
  final _ip = TextEditingController();
  final _port = TextEditingController();
  String _protocol = 'ssh';
  final Set<int> _identities = {};
  List<Identity> _allIdentities = [];

  /// Stored config of the edited entry (merged on save, see
  /// [buildEntryPayload]).
  Map<String, dynamic>? _baseConfig;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _protocols = [
    'ssh',
    'rdp',
    'vnc',
    'sftp',
    'telnet',
    'ftp',
    'ftps'
  ];

  bool get _isCreate => widget.entryId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _ip.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<Identity> identities = const [];
    try {
      final raw = await widget.api.fetchIdentities(widget.token);
      identities = raw
          .map((m) {
            try {
              return Identity.fromJson(m);
            } catch (_) {
              return null;
            }
          })
          .whereType<Identity>()
          .toList();
    } catch (_) {
      // Identities are optional for the form.
    }
    Map<String, dynamic>? detail;
    if (!_isCreate) {
      try {
        detail = await widget.api
            .fetchEntry(widget.token, widget.entryId!);
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = e is NextermApiException
                ? e.message
                : 'Could not load server.';
            _loading = false;
          });
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _allIdentities = identities;
      if (detail != null) {
        _name.text = detail['name'] as String? ?? '';
        final config = detail['config'];
        final cfg = config is Map
            ? Map<String, dynamic>.from(config)
            : <String, dynamic>{};
        _baseConfig = cfg;
        _ip.text = cfg['ip'] as String? ?? detail['ip'] as String? ?? '';
        final port = cfg['port'] ?? detail['port'];
        _port.text = port == null ? '' : '$port';
        final protocol =
            cfg['protocol'] as String? ?? detail['protocol'] as String?;
        if (protocol != null && _protocols.contains(protocol)) {
          _protocol = protocol;
        }
        final ids = detail['identities'];
        if (ids is List) {
          for (final id in ids) {
            final n = id is num ? id.toInt() : int.tryParse('$id');
            if (n != null) _identities.add(n);
          }
        }
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final ip = _ip.text.trim();
    if (name.isEmpty || ip.isEmpty) {
      setState(() => _error = 'Name and IP/hostname are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = buildEntryPayload(
        name: name,
        protocol: _protocol,
        ip: ip,
        port: int.tryParse(_port.text.trim()),
        identities: _identities.toList(),
        baseConfig: _isCreate ? null : _baseConfig,
      );
      if (_isCreate) {
        await widget.api.createEntry(widget.token, payload);
      } else {
        await widget.api.updateEntry(widget.token, widget.entryId!, payload);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is NextermApiException
              ? e.message
              : 'Could not save server.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_isCreate ? 'New server' : 'Edit server')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _protocol,
                  decoration: const InputDecoration(
                    labelText: 'Protocol',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final p in _protocols)
                      DropdownMenuItem(
                          value: p, child: Text(p.toUpperCase())),
                  ],
                  onChanged: (v) =>
                      setState(() => _protocol = v ?? 'ssh'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ip,
                  decoration: const InputDecoration(
                    labelText: 'IP / hostname',
                    hintText: '192.168.1.10',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _port,
                  decoration: const InputDecoration(
                    labelText: 'Port (optional)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                Text('Identities',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_allIdentities.isEmpty)
                  Text('No identities available.',
                      style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant))
                else
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final identity in _allIdentities)
                        FilterChip(
                          label: Text(identity.name),
                          selected:
                              _identities.contains(identity.id),
                          onSelected: (on) => setState(() {
                            if (on) {
                              _identities.add(identity.id);
                            } else {
                              _identities.remove(identity.id);
                            }
                          }),
                        ),
                    ],
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                      : Text(_isCreate ? 'Create' : 'Save'),
                ),
              ],
            ),
    );
  }
}
