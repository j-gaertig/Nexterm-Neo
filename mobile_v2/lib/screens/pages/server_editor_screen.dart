import 'package:flutter/material.dart';

import '../../api/nexterm_api.dart';
import '../../servers/folder_picker.dart';
import '../../servers/identity.dart';
import '../../servers/org_models.dart';
import '../../servers/server_models.dart';

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
  int? folderId,
  bool includeFolder = false,
  Map<String, dynamic>? configExtras,
  String? icon,
  int? organizationId,
  bool includeOrganization = false,
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
  final extras = configExtras;
  if (extras != null) {
    for (final e in extras.entries) {
      if (e.value == null) {
        config.remove(e.key);
      } else {
        config[e.key] = e.value;
      }
    }
  }
  final payload = <String, dynamic>{
    'name': name,
    'type': 'server',
    'config': config,
    'identities': identities,
  };
  if (includeFolder) payload['folderId'] = folderId;
  if (includeOrganization) payload['organizationId'] = organizationId;
  final iconName = icon;
  if (iconName != null) payload['icon'] = iconName;
  return payload;
}

/// Create (`entryId == null`) or edit a server entry.
class ServerEditorScreen extends StatefulWidget {
  const ServerEditorScreen(
      {super.key,
      required this.api,
      required this.token,
      this.entryId,
      this.onSessionExpired});

  final NextermApi api;
  final String token;
  final int? entryId;

  /// Called on HTTP 401 so expired sessions return to login.
  final VoidCallback? onSessionExpired;

  @override
  State<ServerEditorScreen> createState() => _ServerEditorScreenState();
}

class _ServerEditorScreenState extends State<ServerEditorScreen> {
  final _name = TextEditingController();
  final _ip = TextEditingController();
  final _port = TextEditingController();
  final _icon = TextEditingController();
  final _mac = TextEditingController();
  final _wolBroadcast = TextEditingController();
  final _preLocal = TextEditingController();
  final _preRemote = TextEditingController();
  final _afterLocal = TextEditingController();
  final _afterRemote = TextEditingController();
  final _keyboardLayout = TextEditingController();
  String _protocol = 'ssh';
  final Set<int> _identities = {};
  List<Identity> _allIdentities = [];

  /// Stored config of the edited entry (merged on save, see
  /// [buildEntryPayload]).
  Map<String, dynamic>? _baseConfig;

  // -- Advanced section (web ServerDialog parity) -----------------------
  List<FolderNode> _folders = [];
  List<OrgRef> _orgs = [];
  int? _folderId;
  bool _folderTouched = false;
  int? _organizationId;
  bool _organizationTouched = false;
  bool _monitoringEnabled = true;
  bool _wolEnabled = false;
  String _preOrder = 'local-first';
  String _afterOrder = 'local-first';
  String? _rdpSecurity;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isSshLike =>
      _protocol == 'ssh' || _protocol == 'telnet';
  bool get _isGraphical => _protocol == 'rdp' || _protocol == 'vnc';

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
    _icon.dispose();
    _mac.dispose();
    _wolBroadcast.dispose();
    _preLocal.dispose();
    _preRemote.dispose();
    _afterLocal.dispose();
    _afterRemote.dispose();
    _keyboardLayout.dispose();
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
      } on SessionExpiredException {
        if (mounted) setState(() => _loading = false);
        widget.onSessionExpired?.call();
        return;
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
    List<FolderNode> folders = const [];
    try {
      final tree = await widget.api.fetchEntries(widget.token);
      folders = flattenFolderNodes(parseEntryTree(tree));
    } catch (_) {
      // Folder placement is optional for the form.
    }
    final orgs = await loadOrgRefs(
        () => widget.api.fetchOrganizations(widget.token));
    if (!mounted) return;
    setState(() {
      _allIdentities = identities;
      _folders = folders;
      _orgs = orgs;
      if (detail != null) {
        _name.text = detail['name'] as String? ?? '';
        _icon.text = detail['icon'] as String? ?? '';
        final rawFolder = detail['folderId'];
        _folderId = rawFolder is num
            ? rawFolder.toInt()
            : int.tryParse('$rawFolder');
        final rawOrg = detail['organizationId'];
        _organizationId = rawOrg is num
            ? rawOrg.toInt()
            : int.tryParse('$rawOrg');
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
        _monitoringEnabled = cfg['monitoringEnabled'] != false;
        _mac.text = cfg['macAddress'] as String? ?? '';
        _wolEnabled = cfg['wakeOnLanEnabled'] == true;
        _wolBroadcast.text =
            cfg['wolBroadcastAddress'] as String? ?? '';
        _preLocal.text = cfg['preLocalCommand'] as String? ?? '';
        _preRemote.text = cfg['preRemoteCommand'] as String? ?? '';
        _afterLocal.text = cfg['afterLocalCommand'] as String? ?? '';
        _afterRemote.text = cfg['afterRemoteCommand'] as String? ?? '';
        final preOrder = cfg['preOrder'];
        if (preOrder == 'local-first' || preOrder == 'remote-first') {
          _preOrder = preOrder as String;
        }
        final afterOrder = cfg['afterOrder'];
        if (afterOrder == 'local-first' ||
            afterOrder == 'remote-first') {
          _afterOrder = afterOrder as String;
        }
        _keyboardLayout.text =
            cfg['keyboardLayout'] as String? ?? '';
        const securities = ['any', 'nla', 'tls', 'rdp', 'vmconnect'];
        final security = cfg['rdpSecurity'] as String?;
        if (security != null && securities.contains(security)) {
          _rdpSecurity = security;
        }
      }
      _loading = false;
    });
  }

  /// Advanced config keys (web ServerDialog parity). Empty values are
  /// omitted on create; on edit they overwrite (empty string clears).
  /// `monitoringEnabled` defaults to on — only an explicit off is sent
  /// on create so new servers keep the server default.
  Map<String, dynamic> _configExtras() {
    final extras = <String, dynamic>{};
    void put(String key, String value) {
      final v = value.trim();
      if (_isCreate) {
        if (v.isNotEmpty) extras[key] = v;
      } else {
        extras[key] = v;
      }
    }

    if (_protocol == 'ssh') {
      if (_isCreate) {
        if (!_monitoringEnabled) {
          extras['monitoringEnabled'] = false;
        }
      } else {
        extras['monitoringEnabled'] = _monitoringEnabled;
      }
    }
    if (_isSshLike || _isGraphical) {
      put('macAddress', _mac.text);
      if (!_isCreate || _wolEnabled) {
        extras['wakeOnLanEnabled'] = _wolEnabled;
      }
      put('wolBroadcastAddress', _wolBroadcast.text);
    }
    if (_protocol == 'ssh') {
      put('preLocalCommand', _preLocal.text);
      put('preRemoteCommand', _preRemote.text);
      put('afterLocalCommand', _afterLocal.text);
      put('afterRemoteCommand', _afterRemote.text);
      if (!_isCreate ||
          _preLocal.text.trim().isNotEmpty ||
          _preRemote.text.trim().isNotEmpty) {
        extras['preOrder'] = _preOrder;
      }
      if (!_isCreate ||
          _afterLocal.text.trim().isNotEmpty ||
          _afterRemote.text.trim().isNotEmpty) {
        extras['afterOrder'] = _afterOrder;
      }
    }
    if (_isGraphical) {
      put('keyboardLayout', _keyboardLayout.text);
    }
    if (_protocol == 'rdp') {
      final security = _rdpSecurity;
      if (security != null && (!_isCreate || security != 'any')) {
        extras['rdpSecurity'] = security;
      }
    }
    return extras;
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
      final extras = _configExtras();
      final iconText = _icon.text.trim();
      final payload = buildEntryPayload(
        name: name,
        protocol: _protocol,
        ip: ip,
        port: int.tryParse(_port.text.trim()),
        identities: _identities.toList(),
        baseConfig: _isCreate ? null : _baseConfig,
        folderId: _folderId,
        includeFolder: _isCreate ? _folderId != null : _folderTouched,
        configExtras: extras.isEmpty ? null : extras,
        icon: iconText.isEmpty ? null : iconText,
        organizationId: _organizationId,
        includeOrganization: _isCreate
            ? _organizationId != null
            : _organizationTouched,
      );
      if (_isCreate) {
        await widget.api.createEntry(widget.token, payload);
      } else {
        await widget.api.updateEntry(widget.token, widget.entryId!, payload);
      }
      if (mounted) Navigator.pop(context, true);
    } on SessionExpiredException {
      if (mounted) setState(() => _saving = false);
      widget.onSessionExpired?.call();
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
                TextField(
                  controller: _icon,
                  decoration: const InputDecoration(
                    labelText: 'Icon name (optional)',
                    hintText: 'server, database, …',
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
                const SizedBox(height: 24),
                Text('Advanced',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  initialValue: _folderId,
                  decoration: const InputDecoration(
                    labelText: 'Folder',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('Top level')),
                    for (final folder in _folders)
                      DropdownMenuItem<int?>(
                        value: int.tryParse(folder.id),
                        child: Text(folder.name),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _folderId = v;
                    _folderTouched = true;
                  }),
                ),
                if (_orgs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: _organizationId,
                    decoration: const InputDecoration(
                      labelText: 'Organization',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Personal')),
                      for (final org in _orgs)
                        DropdownMenuItem<int?>(
                          value: org.id,
                          child: Text(org.name),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _organizationId = v;
                      _organizationTouched = true;
                    }),
                  ),
                ],
                if (_protocol == 'ssh') ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Monitoring',
                        style: TextStyle(
                            fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                        'Collect metrics for this server',
                        style: TextStyle(fontSize: 12)),
                    value: _monitoringEnabled,
                    onChanged: (v) =>
                        setState(() => _monitoringEnabled = v),
                  ),
                ],
                if (_isSshLike || _isGraphical) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Wake on LAN',
                        style: TextStyle(
                            fontWeight: FontWeight.w600)),
                    value: _wolEnabled,
                    onChanged: (v) =>
                        setState(() => _wolEnabled = v),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _mac,
                    decoration: const InputDecoration(
                      labelText: 'MAC address (WoL)',
                      hintText: 'AA:BB:CC:DD:EE:FF',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _wolBroadcast,
                    decoration: const InputDecoration(
                      labelText: 'Broadcast address (optional)',
                      hintText: '192.168.1.255',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ],
                if (_protocol == 'ssh') ...[
                  const SizedBox(height: 16),
                  Text('Connection hooks',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _preLocal,
                    decoration: const InputDecoration(
                      labelText: 'Before connect (local)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _preRemote,
                    decoration: const InputDecoration(
                      labelText: 'Before connect (remote)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _preOrder,
                    decoration: const InputDecoration(
                      labelText: 'Before order',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'local-first',
                          child: Text('Local first')),
                      DropdownMenuItem(
                          value: 'remote-first',
                          child: Text('Remote first')),
                    ],
                    onChanged: (v) => setState(
                        () => _preOrder = v ?? 'local-first'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _afterLocal,
                    decoration: const InputDecoration(
                      labelText: 'After disconnect (local)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _afterRemote,
                    decoration: const InputDecoration(
                      labelText: 'After disconnect (remote)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _afterOrder,
                    decoration: const InputDecoration(
                      labelText: 'After order',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'local-first',
                          child: Text('Local first')),
                      DropdownMenuItem(
                          value: 'remote-first',
                          child: Text('Remote first')),
                    ],
                    onChanged: (v) => setState(
                        () => _afterOrder = v ?? 'local-first'),
                  ),
                ],
                if (_isGraphical) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keyboardLayout,
                    decoration: const InputDecoration(
                      labelText: 'Keyboard layout (optional)',
                      hintText: 'en-us',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_protocol == 'rdp') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _rdpSecurity,
                    decoration: const InputDecoration(
                      labelText: 'Security (optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'any', child: Text('Any')),
                      DropdownMenuItem(
                          value: 'nla', child: Text('NLA')),
                      DropdownMenuItem(
                          value: 'tls', child: Text('TLS')),
                      DropdownMenuItem(
                          value: 'rdp', child: Text('RDP')),
                      DropdownMenuItem(
                          value: 'vmconnect',
                          child: Text('VMConnect')),
                    ],
                    onChanged: (v) =>
                        setState(() => _rdpSecurity = v),
                  ),
                ],
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
