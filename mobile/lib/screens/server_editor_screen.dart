import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/managed_identity.dart';
import '../models/server.dart';
import '../models/server_details.dart';
import '../services/server_editor_service.dart';
import '../services/server_service.dart';
import '../utils/app_icons.dart';
import '../utils/server_field_config.dart';

class FolderOption {
  final dynamic id;
  final String name;
  final String type;
  final dynamic organizationId;
  const FolderOption({this.id, required this.name, this.type = 'folder', this.organizationId});
}

class ServerEditorScreen extends StatefulWidget {
  final String token;
  final dynamic editServerId;
  final String? initialProtocol;
  final dynamic initialFolderId;
  final dynamic initialOrganizationId;
  final List<FolderOption> folderOptions;

  const ServerEditorScreen({
    super.key,
    required this.token,
    this.editServerId,
    this.initialProtocol,
    this.initialFolderId,
    this.initialOrganizationId,
    this.folderOptions = const [],
  });

  @override
  State<ServerEditorScreen> createState() => _ServerEditorScreenState();
}

class _ServerEditorScreenState extends State<ServerEditorScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<String> _tabKeys = ['details'];

  final _name = TextEditingController();
  final _ip = TextEditingController();
  final _port = TextEditingController();
  final _mac = TextEditingController();
  final _wolBroadcast = TextEditingController();
  final _preLocal = TextEditingController();
  final _preRemote = TextEditingController();
  final _afterLocal = TextEditingController();
  final _afterRemote = TextEditingController();
  final _iconCustom = TextEditingController();

  String? _icon;
  String? _protocol;
  String? _engineId;
  List<EngineInfo> _engines = [];
  dynamic _folderId;
  dynamic _organizationId;

  bool _monitoringEnabled = false;
  bool _wakeOnLanEnabled = false;
  bool _enableAudio = true;
  bool _enableWallpaper = true;
  bool _enableTheming = true;
  bool _enableFontSmoothing = true;
  bool _enableFullWindowDrag = false;
  bool _enableDesktopComposition = false;
  bool _enableMenuAnimations = false;

  String _colorDepth = '';
  String _resizeMethod = 'display-update';
  String _rdpSecurity = '';
  String _keyboardLayout = 'en-us-qwerty';
  String _backspaceMode = 'del';
  String _deleteMode = 'vt';
  String _functionKeyMode = 'xterm';
  String _preOrder = 'local-first';
  String _afterOrder = 'remote-first';
  List<dynamic> _jumpHosts = [];
  List<Server> _sshCandidates = [];
  // Full config as loaded from the backend. The mobile editor only manages a
  // subset of keys; the rest (e.g. notes/showNoteInList, which are web-only)
  // must be passed through untouched so editing doesn't reset them.
  Map<String, dynamic> _originalConfig = {};

  List<int> _linkedIds = [];
  Map<String, IdentityDraft> _drafts = {};
  List<ManagedIdentity> _allIdentities = [];

  bool get _isEdit => widget.editServerId != null;
  ServerFieldConfig get _fieldConfig => getServerFieldConfig('server', _protocol);
  List<String> get _allowedAuth => _fieldConfig.allowedAuthTypes;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 1, vsync: this);
    _folderId = widget.initialFolderId;
    _organizationId = widget.initialOrganizationId;
    _init();
  }

  @override
  void dispose() {
    _name.dispose();
    _ip.dispose();
    _port.dispose();
    _mac.dispose();
    _wolBroadcast.dispose();
    _preLocal.dispose();
    _preRemote.dispose();
    _afterLocal.dispose();
    _afterRemote.dispose();
    _iconCustom.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _rebuildTabs() {
    if (!mounted) return;
    final keys = getServerTabs('server', _protocol);
    setState(() {
      _tabKeys = keys;
      _tabs.dispose();
      _tabs = TabController(length: keys.length, vsync: this, initialIndex: 0);
    });
  }

  void _sanitizeDrafts() {
    for (final draft in _drafts.values) {
      if (!_allowedAuth.contains(draft.authType)) {
        draft.authType = _allowedAuth.isNotEmpty ? _allowedAuth.first : 'password';
      }
    }
  }

  void _syncIconCustom() {
    final text = _icon ?? '';
    if (_iconCustom.text != text) {
      _iconCustom.text = text;
      _iconCustom.selection = TextSelection.fromPosition(TextPosition(offset: _iconCustom.text.length));
    }
  }

  String _validOr(String value, List<Map<String, String>> options, String fallback) {
    return options.any((o) => o['value'] == value) ? value : fallback;
  }

  List<DropdownMenuItem<String>> _protocolItems() {
    final items = [
      for (final p in ServerEditorConstants.protocols)
        DropdownMenuItem(value: p['value'], child: Text(p['label']!)),
    ];
    if (_protocol != null &&
        !ServerEditorConstants.protocols.any((p) => p['value'] == _protocol) &&
        _protocol!.isNotEmpty) {
      items.add(DropdownMenuItem(value: _protocol, child: Text(_protocol!.toUpperCase())));
    }
    return items;
  }

  void _onProtocolChanged(String? value) {
    final old = _protocol;
    setState(() {
      _protocol = value;
      if (value != null) {
        final oldDefault = old == null ? '' : (ServerEditorConstants.defaultPorts[old] ?? '');
        if (_port.text.isEmpty || (_port.text == oldDefault && oldDefault.isNotEmpty)) {
          _port.text = ServerEditorConstants.defaultPorts[value] ?? _port.text;
        }
      }
      if (value != null && (_icon == null || ServerEditorConstants.protocolIcons.containsValue(_icon))) {
        _icon = ServerEditorConstants.protocolIcons[value];
        _syncIconCustom();
      }
      if (!_fieldConfig.showIdentities) {
        _linkedIds = [];
        _drafts.clear();
      } else {
        _linkedIds = _linkedIds.where((id) {
          final matches = _allIdentities.where((e) => e.id.toString() == id.toString());
          if (matches.isEmpty) return true;
          return _allowedAuth.contains(matches.first.authType);
        }).toList();
        _drafts.removeWhere((key, draft) => !_allowedAuth.contains(draft.authType));
      }
    });
    _sanitizeDrafts();
    _rebuildTabs();
  }

  Future<void> _init() async {
    try {
      final enginesFuture = ServerEditorService.getEngines(widget.token);
      final identitiesFuture = ServerEditorService.getIdentities(widget.token);
      List<Server> sshCandidates = [];
      try {
        final items = await ServerService.getServerList(widget.token);
        sshCandidates = _collectSsh(items);
      } catch (_) {}
      final engines = await enginesFuture;
      if (!mounted) return;
      final identities = await identitiesFuture;
      if (!mounted) return;
      if (_isEdit) {
        final details = await ServerEditorService.getEntry(widget.token, widget.editServerId);
        if (!mounted) return;
        _applyDetails(details);
        _sshCandidates = sshCandidates.where((s) => s.id.toString() != widget.editServerId.toString()).toList();
        if (_engineId == null && engines.isNotEmpty) {
          _engineId = engines.first.id?.toString();
        }
        setState(() {
          _engines = engines;
          _allIdentities = identities;
          _loading = false;
        });
      } else {
        _protocol = widget.initialProtocol;
        if (_protocol != null) {
          _port.text = ServerEditorConstants.defaultPorts[_protocol] ?? '';
          _icon = ServerEditorConstants.protocolIcons[_protocol];
          _syncIconCustom();
        }
        if (_engineId == null && engines.isNotEmpty) {
          _engineId = engines.first.id?.toString();
        }
        _sshCandidates = sshCandidates;
        setState(() {
          _engines = engines;
          _allIdentities = identities;
          _loading = false;
        });
      }
      _rebuildTabs();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Server> _collectSsh(List<dynamic> items) {
    final out = <Server>[];
    for (final item in items) {
      if (item is Server) {
        if (item.protocol?.toLowerCase() == 'ssh' && item.isServer) out.add(item);
      } else {
        try {
          final dyn = item as dynamic;
          final servers = dyn.allServers as List<Server>;
          for (final s in servers) {
            if (s.protocol?.toLowerCase() == 'ssh' && s.isServer) out.add(s);
          }
          final folders = dyn.allFolders as List;
          out.addAll(_collectSsh(folders));
        } catch (_) {}
      }
    }
    return out;
  }

  void _applyDetails(ServerDetails details) {
    final c = details.config;
    _originalConfig = Map<String, dynamic>.from(c);
    _name.text = details.name;
    _icon = details.icon;
    _syncIconCustom();
    _protocol = c['protocol']?.toString()?.toLowerCase();
    _ip.text = (c['ip'] ?? '').toString();
    _port.text = (c['port'] ?? '').toString();
    _mac.text = (c['macAddress'] ?? '').toString();
    _wolBroadcast.text = (c['wolBroadcastAddress'] ?? '').toString();
    final engineId = c['engineId'];
    _engineId = engineId?.toString();
    _folderId = details.folderId;
    _organizationId = details.organizationId;
    _monitoringEnabled = (c['monitoringEnabled'] ?? true) == true;
    _wakeOnLanEnabled = c['wakeOnLanEnabled'] == true;
    if (c['enableAudio'] != null) _enableAudio = c['enableAudio'] == true;
    if (c['enableWallpaper'] != null) _enableWallpaper = c['enableWallpaper'] == true;
    if (c['enableTheming'] != null) _enableTheming = c['enableTheming'] == true;
    if (c['enableFontSmoothing'] != null) _enableFontSmoothing = c['enableFontSmoothing'] == true;
    if (c['enableFullWindowDrag'] != null) _enableFullWindowDrag = c['enableFullWindowDrag'] == true;
    if (c['enableDesktopComposition'] != null) _enableDesktopComposition = c['enableDesktopComposition'] == true;
    if (c['enableMenuAnimations'] != null) _enableMenuAnimations = c['enableMenuAnimations'] == true;
    _colorDepth = _validOr(c['colorDepth']?.toString() ?? '', ServerEditorConstants.colorDepths, '');
    _resizeMethod =
        _validOr(c['resizeMethod']?.toString() ?? 'display-update', ServerEditorConstants.resizeMethods, 'display-update');
    _rdpSecurity =
        _validOr(c['rdpSecurity']?.toString() ?? '', ServerEditorConstants.rdpSecurityMethods, '');
    _keyboardLayout = _validOr(c['keyboardLayout']?.toString() ?? 'en-us-qwerty',
        ServerEditorConstants.keyboardLayouts, 'en-us-qwerty');
    _backspaceMode =
        _validOr(c['backspaceMode']?.toString() ?? 'del', ServerEditorConstants.backspaceModes, 'del');
    _deleteMode = _validOr(c['deleteMode']?.toString() ?? 'vt', ServerEditorConstants.deleteModes, 'vt');
    _functionKeyMode =
        _validOr(c['functionKeyMode']?.toString() ?? 'xterm', ServerEditorConstants.functionKeyModes, 'xterm');
    _preOrder = _validOr(
        c['preOrder']?.toString() ?? 'local-first', const [
      {'label': 'Local first', 'value': 'local-first'},
      {'label': 'Remote first', 'value': 'remote-first'},
    ], 'local-first');
    _afterOrder = _validOr(
        c['afterOrder']?.toString() ?? 'remote-first', const [
      {'label': 'Local first', 'value': 'local-first'},
      {'label': 'Remote first', 'value': 'remote-first'},
    ], 'remote-first');
    _preLocal.text = (c['preLocalCommand'] ?? '').toString();
    _preRemote.text = (c['preRemoteCommand'] ?? '').toString();
    _afterLocal.text = (c['afterLocalCommand'] ?? '').toString();
    _afterRemote.text = (c['afterRemoteCommand'] ?? '').toString();
    final jh = c['jumpHosts'];
    if (jh is List) _jumpHosts = List<dynamic>.from(jh);
    _linkedIds = List<int>.from(details.identities);
  }

  Map<String, dynamic> _buildConfig() {
    final fc = _fieldConfig;
    final config = <String, dynamic>{};
    if (fc.showIpPort) {
      config['protocol'] = _protocol;
      config['ip'] = _ip.text.trim();
      config['port'] = _port.text.trim();
      final engineValue = _engineValue();
      if (engineValue != null && engineValue.isNotEmpty) config['engineId'] = engineValue;
      if (_wakeOnLanEnabled || _mac.text.trim().isNotEmpty) {
        config['macAddress'] = _mac.text.trim();
      }
      if (_wakeOnLanEnabled || _wolBroadcast.text.trim().isNotEmpty) {
        config['wolBroadcastAddress'] = _wolBroadcast.text.trim();
      }
    } else {
      config['protocol'] = _protocol;
    }
    if (fc.showMonitoring) config['monitoringEnabled'] = _monitoringEnabled;
    if (fc.showWakeOnLan) config['wakeOnLanEnabled'] = _wakeOnLanEnabled;
    if (fc.showKeyboardLayout) config['keyboardLayout'] = _keyboardLayout;
    if (fc.showDisplaySettings) {
      config['colorDepth'] = _colorDepth;
      config['resizeMethod'] = _resizeMethod;
    }
    if (fc.showAudioSettings) config['enableAudio'] = _enableAudio;
    if (fc.showPerformanceSettings) {
      config['enableWallpaper'] = _enableWallpaper;
      config['enableTheming'] = _enableTheming;
      config['enableFontSmoothing'] = _enableFontSmoothing;
      config['enableFullWindowDrag'] = _enableFullWindowDrag;
      config['enableDesktopComposition'] = _enableDesktopComposition;
      config['enableMenuAnimations'] = _enableMenuAnimations;
    }
    if (fc.showRdpSecurity) config['rdpSecurity'] = _rdpSecurity;
    if (fc.showTerminalSettings) {
      config['backspaceMode'] = _backspaceMode;
      config['deleteMode'] = _deleteMode;
      config['functionKeyMode'] = _functionKeyMode;
    }
    if (_protocol == 'ssh') {
      config['jumpHosts'] = _jumpHosts;
      if (fc.showConnectionHooks) {
        config['preLocalCommand'] = _preLocal.text;
        config['preRemoteCommand'] = _preRemote.text;
        config['preOrder'] = _preOrder;
        config['afterLocalCommand'] = _afterLocal.text;
        config['afterRemoteCommand'] = _afterRemote.text;
        config['afterOrder'] = _afterOrder;
      }
    }
    // Preserve web-only fields that this editor doesn't manage. Only pass
    // through values with the expected type: null/legacy values are omitted
    // so the request stays valid and the backend keeps the stored value.
    final notes = _originalConfig['notes'];
    if (notes is String) config['notes'] = notes;
    final showNoteInList = _originalConfig['showNoteInList'];
    if (showNoteInList is bool) config['showNoteInList'] = showNoteInList;
    return config;
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final config = _buildConfig();
    if (!validateServerFields('server', _protocol, name, config)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (_drafts.values.any((d) => d.name.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identity names must not be empty'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final ids = await ServerEditorService.syncIdentities(
        token: widget.token,
        currentIds: _linkedIds,
        drafts: _drafts,
      );
      if (_isEdit) {
        await ServerEditorService.updateEntry(
          token: widget.token,
          entryId: widget.editServerId,
          name: name,
          icon: _icon,
          config: config,
          identities: ids,
        );
      } else {
        await ServerEditorService.createEntry(
          token: widget.token,
          name: name,
          icon: _icon,
          config: config,
          folderId: _folderId is int ? _folderId : int.tryParse((_folderId ?? '').toString()),
          organizationId: _organizationId is int
              ? _organizationId
              : int.tryParse((_organizationId ?? '').toString()),
          identities: ids,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit
            ? 'Edit server'
            : (_protocol == null || _protocol!.isEmpty)
                ? 'New server'
                : 'New ${_protocol!.toUpperCase()} server'),
        bottom: _loading
            ? null
            : TabBar(
                controller: _tabs,
                tabs: [for (final k in _tabKeys) Tab(text: _tabLabel(k))],
              ),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.alertCircleOutline, size: 40, color: cs.error),
                        const SizedBox(height: 12),
                        Text(_error!, style: tt.bodyMedium, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [for (final k in _tabKeys) _tabView(k)],
                ),
    );
  }

  String _tabLabel(String key) {
    switch (key) {
      case 'identities':
        return 'Identities';
      case 'settings':
        return 'Settings';
      default:
        return 'Details';
    }
  }

  Widget _tabView(String key) {
    switch (key) {
      case 'identities':
        return _identitiesTab();
      case 'settings':
        return _settingsTab();
      default:
        return _detailsTab();
    }
  }

  InputDecoration _dec(String? hint, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary, width: 1.5)),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2, top: 14),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.outline)),
      );

  Widget _detailsTab() {
    final cs = Theme.of(context).colorScheme;
    final fc = _fieldConfig;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isEdit && _organizationId != null && _folderId == null) ...[
            _label('Location'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(AppIcons.brandDomain, size: 20, color: cs.primary),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Organization server', overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ],
          if (!_isEdit && !(_organizationId != null && _folderId == null) && widget.folderOptions.isNotEmpty) ...[
            _label('Folder'),
            DropdownButtonFormField<String?>(
              initialValue: _folderId?.toString(),
              decoration: _dec(null, AppIcons.brandFolder),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Root')),
                for (final f in widget.folderOptions)
                  DropdownMenuItem<String?>(value: f.id?.toString(), child: Text(f.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                setState(() {
                  _folderId = v == null ? null : int.tryParse(v) ?? v;
                  if (v == null) {
                    _organizationId = null;
                  } else {
                    final match = widget.folderOptions.where((f) => f.id?.toString() == v);
                    _organizationId = match.isEmpty ? null : match.first.organizationId;
                  }
                });
              },
            ),
          ],
          _label('Name'),
          TextField(controller: _name, decoration: _dec('Server name', AppIcons.pencilOutline), textCapitalization: TextCapitalization.words),
          _label('Icon'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final iconName in ServerEditorConstants.iconOptions)
                GestureDetector(
                  onTap: () => setState(() {
                    _icon = iconName;
                    _syncIconCustom();
                  }),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _icon == iconName ? cs.primaryContainer : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: _icon == iconName ? Border.all(color: cs.primary, width: 1.5) : null,
                    ),
                    child: Icon(AppIcons.resolveBackendIcon(_iconKey(iconName)) ?? AppIcons.brandServer,
                        size: 20, color: _icon == iconName ? cs.onPrimaryContainer : cs.outline),
                  ),
                ),
            ],
          ),
          _label('Custom icon name (e.g. mdiServer, mdiConsole)'),
          TextField(
            controller: _iconCustom,
            decoration: _dec('mdiServer', AppIcons.pencilOutline),
            onChanged: (v) => setState(() => _icon = v.trim().isEmpty ? null : v.trim()),
          ),
          if (_engines.length > 1) ...[
            _label('Engine'),
            DropdownButtonFormField<String>(
              initialValue: _engineValue(),
              decoration: _dec(null, AppIcons.serverNetwork),
              items: [
                for (final e in _engines)
                  DropdownMenuItem(
                      value: e.id?.toString(),
                      child: Text(e.connected ? e.name : "${e.name} (offline)", overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _engineId = v),
            ),
          ],
          if (fc.showIpPort) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Server IP'),
                      TextField(controller: _ip, decoration: _dec('192.168.1.10', AppIcons.serverNetwork), keyboardType: TextInputType.text),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Port'),
                      TextField(controller: _port, decoration: _dec('22', AppIcons.connection), keyboardType: TextInputType.number),
                    ],
                  ),
                ),
              ],
            ),
            ...[
              _label('Protocol'),
              DropdownButtonFormField<String>(
                initialValue: _protocol,
                decoration: _dec(null, AppIcons.connection),
                items: _protocolItems(),
                onChanged: _onProtocolChanged,
              ),
            ],
            if (_wakeOnLanEnabled) ...[
              _label('MAC address'),
              TextField(controller: _mac, decoration: _dec('AA:BB:CC:DD:EE:FF', AppIcons.serverNetwork)),
              _label('WoL broadcast address'),
              TextField(controller: _wolBroadcast, decoration: _dec('192.168.1.255', AppIcons.serverNetwork)),
            ],
          ] else ...[
            _label('Protocol'),
            DropdownButtonFormField<String>(
              initialValue: _protocol,
              decoration: _dec(null, AppIcons.connection),
              items: _protocolItems(),
              onChanged: _onProtocolChanged,
            ),
          ],
        ],
      ),
    );
  }

  String _iconKey(String backend) {
    if (backend.startsWith('mdi') && backend.length > 3) {
      return backend.substring(3, 4).toLowerCase() + backend.substring(4);
    }
    return backend;
  }

  Widget _settingsTab() {
    final fc = _fieldConfig;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_protocol == 'ssh') _jumpHostsSection(),
          if (_protocol == 'ssh' && fc.showConnectionHooks) ...[
            _hookGroup(
              title: 'Before connect',
              localController: _preLocal,
              remoteController: _preRemote,
              order: _preOrder,
              onSwap: () => setState(() => _preOrder = _preOrder == 'local-first' ? 'remote-first' : 'local-first'),
            ),
            _hookGroup(
              title: 'After disconnect',
              localController: _afterLocal,
              remoteController: _afterRemote,
              order: _afterOrder,
              onSwap: () => setState(() => _afterOrder = _afterOrder == 'local-first' ? 'remote-first' : 'local-first'),
            ),
          ],
          if (fc.showMonitoring)
            _switchTile(
              title: 'Monitoring',
              subtitle: 'Collect metrics for this server',
              icon: AppIcons.chartBoxOutline,
              value: _monitoringEnabled,
              onChanged: (v) => setState(() => _monitoringEnabled = v),
            ),
          if (fc.showWakeOnLan)
            _switchTile(
              title: 'Wake-On-LAN',
              subtitle: 'Enable magic packet wakeup',
              icon: AppIcons.powerPlug,
              value: _wakeOnLanEnabled,
              onChanged: (v) => setState(() => _wakeOnLanEnabled = v),
            ),
          if (fc.showTerminalSettings) ...[
            _label('Terminal backspace'),
            _optionDropdown(ServerEditorConstants.backspaceModes, _backspaceMode, (v) => setState(() => _backspaceMode = v)),
            _label('Terminal delete'),
            _optionDropdown(ServerEditorConstants.deleteModes, _deleteMode, (v) => setState(() => _deleteMode = v)),
            _label('Function keys'),
            _optionDropdown(ServerEditorConstants.functionKeyModes, _functionKeyMode, (v) => setState(() => _functionKeyMode = v)),
          ],
          if (fc.showRdpSecurity) ...[
            _label('RDP security'),
            _optionDropdown(ServerEditorConstants.rdpSecurityMethods, _rdpSecurity, (v) => setState(() => _rdpSecurity = v)),
          ],
          if (fc.showKeyboardLayout) ...[
            _label('Keyboard layout'),
            DropdownButtonFormField<String>(
              initialValue: ServerEditorConstants.keyboardLayouts.any((k) => k['value'] == _keyboardLayout)
                  ? _keyboardLayout
                  : 'en-us-qwerty',
              decoration: _dec(null, AppIcons.keyboard),
              items: [
                for (final k in ServerEditorConstants.keyboardLayouts)
                  DropdownMenuItem(value: k['value'], child: Text(k['label']!, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _keyboardLayout = v);
              },
            ),
          ],
          if (fc.showDisplaySettings) ...[
            _label('Color depth'),
            _optionDropdown(ServerEditorConstants.colorDepths, _colorDepth, (v) => setState(() => _colorDepth = v)),
            _label('Resize method'),
            _optionDropdown(ServerEditorConstants.resizeMethods, _resizeMethod, (v) => setState(() => _resizeMethod = v)),
          ],
          if (fc.showAudioSettings)
            _switchTile(
              title: 'Enable audio',
              subtitle: 'Forward remote audio',
              icon: AppIcons.microphoneOutline,
              value: _enableAudio,
              onChanged: (v) => setState(() => _enableAudio = v),
            ),
          if (fc.showPerformanceSettings) ...[
            _switchTile(
                title: 'Wallpaper', subtitle: 'Show desktop wallpaper', icon: AppIcons.palette, value: _enableWallpaper, onChanged: (v) => setState(() => _enableWallpaper = v)),
            _switchTile(
                title: 'Theming', subtitle: 'Allow visual styles', icon: AppIcons.palette, value: _enableTheming, onChanged: (v) => setState(() => _enableTheming = v)),
            _switchTile(
                title: 'Font smoothing',
                subtitle: 'Smooth fonts in session',
                icon: AppIcons.formatSize,
                value: _enableFontSmoothing,
                onChanged: (v) => setState(() => _enableFontSmoothing = v)),
            _switchTile(
                title: 'Full window drag',
                subtitle: 'Show contents while dragging',
                icon: AppIcons.cursorDefaultClick,
                value: _enableFullWindowDrag,
                onChanged: (v) => setState(() => _enableFullWindowDrag = v)),
            _switchTile(
                title: 'Desktop composition',
                subtitle: 'Enable composition effects',
                icon: AppIcons.monitorMultiple,
                value: _enableDesktopComposition,
                onChanged: (v) => setState(() => _enableDesktopComposition = v)),
            _switchTile(
                title: 'Menu animations',
                subtitle: 'Animate menus and windows',
                icon: AppIcons.creation,
                value: _enableMenuAnimations,
                onChanged: (v) => setState(() => _enableMenuAnimations = v)),
          ],
        ],
      ),
    );
  }

  Widget _optionDropdown(List<Map<String, String>> options, String value, ValueChanged<String> onChanged) {
    final valid = options.any((o) => o['value'] == value) ? value : (options.isNotEmpty ? options.first['value']! : '');
    return DropdownButtonFormField<String>(
      initialValue: valid,
      decoration: _dec(null, AppIcons.cogOutline),
      items: [for (final o in options) DropdownMenuItem(value: o['value'], child: Text(o['label']!, overflow: TextOverflow.ellipsis))],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: cs.outline)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _jumpHostsSection() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.serverNetwork, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              const Text('Jump hosts', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          Text('Route SSH through other servers in order', style: TextStyle(fontSize: 12, color: cs.outline)),
          const SizedBox(height: 8),
          for (int i = 0; i < _jumpHosts.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                    child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _jumpHostValue(i),
                      decoration: _dec(null, AppIcons.server),
                      items: [
                        for (final s in _availableJumpHosts(i))
                          DropdownMenuItem(value: s.id.toString(), child: Text('${s.name} (${s.ip})', overflow: TextOverflow.ellipsis)),
                        if (_jumpHosts[i] != null &&
                            !_availableJumpHosts(i).any((s) => s.id.toString() == _jumpHosts[i].toString()))
                          DropdownMenuItem(
                              value: _jumpHosts[i].toString(),
                              child: Text('Server ${_jumpHosts[i]} (unavailable)', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          final parsed = int.tryParse(v) ?? v;
                          _jumpHosts[i] = parsed;
                        });
                      },
                    ),
                  ),
                  IconButton(
                    icon: Icon(AppIcons.close, size: 18, color: cs.outline),
                    onPressed: () => setState(() => _jumpHosts.removeAt(i)),
                  ),
                ],
              ),
            ),
          if (_availableJumpHosts(_jumpHosts.length).isNotEmpty)
            OutlinedButton.icon(
              onPressed: () {
                final avail = _availableJumpHosts(_jumpHosts.length);
                if (avail.isEmpty) return;
                setState(() {
                  final first = avail.first;
                  final parsed = int.tryParse(first.id.toString());
                  _jumpHosts.add(parsed ?? first.id);
                });
              },
              icon: Icon(AppIcons.plus, size: 16),
              label: const Text('Add jump host'),
            )
          else
            Text(
              _sshCandidates.isEmpty ? 'No SSH servers available' : 'All SSH servers already added',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
        ],
      ),
    );
  }

  List<Server> _availableJumpHosts(int index) {
    final selected = <String>{};
    for (int i = 0; i < _jumpHosts.length; i++) {
      if (i == index) continue;
      selected.add(_jumpHosts[i].toString());
    }
    return _sshCandidates.where((s) => !selected.contains(s.id.toString())).toList();
  }

  String? _jumpHostValue(int index) {
    if (index < 0 || index >= _jumpHosts.length) return null;
    return _jumpHosts[index]?.toString();
  }

  String? _engineValue() {
    if (_engines.isEmpty) return null;
    final ids = _engines.map((e) => e.id?.toString()).toSet();
    if (_engineId != null && ids.contains(_engineId)) return _engineId;
    return _engines.first.id?.toString();
  }

  bool get _engineOffline {
    if (_engineId == null || _engineId!.isEmpty) return false;
    if (_engines.isEmpty) return true;
    final match = _engines.where((e) => e.id?.toString() == _engineId);
    if (match.isEmpty) return true;
    return !match.first.connected;
  }

  Widget _hookGroup({
    required String title,
    required TextEditingController localController,
    required TextEditingController remoteController,
    required String order,
    required VoidCallback onSwap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final firstIsLocal = order != 'remote-first';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
              IconButton(onPressed: onSwap, icon: Icon(AppIcons.refresh, size: 18, color: cs.primary)),
            ],
          ),
          _hookField(
              label: firstIsLocal ? 'Local (1st)' : 'Remote (1st)',
              controller: firstIsLocal ? localController : remoteController),
          const SizedBox(height: 8),
          _hookField(
              label: firstIsLocal ? 'Remote (2nd)' : 'Local (2nd)',
              controller: firstIsLocal ? remoteController : localController),
          if (_engineOffline)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Selected engine is offline, remote hooks run on fallback engine',
                  style: TextStyle(fontSize: 11, color: cs.outline)),
            ),
        ],
      ),
    );
  }

  Widget _hookField({required String label, required TextEditingController controller}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLength: 2000,
          decoration: _dec('command', AppIcons.consoleLine),
        ),
      ],
    );
  }

  List<ManagedIdentity> _linkedOrg() {
    return _linkedIds
        .map((id) => _allIdentities.where((e) => e.id.toString() == id.toString()))
        .where((it) => it.isNotEmpty)
        .map((it) => it.first)
        .where((e) => e.isOrg)
        .toList();
  }

  List<ManagedIdentity> _linkedPersonal() {
    return _linkedIds
        .map((id) => _allIdentities.where((e) => e.id.toString() == id.toString()))
        .where((it) => it.isNotEmpty)
        .map((it) => it.first)
        .where((e) => !e.isOrg)
        .toList();
  }

  List<ManagedIdentity> _availableFor(bool org) {
    final linked = _linkedIds.map((e) => e.toString()).toSet();
    return _allIdentities.where((e) {
      if (linked.contains(e.id.toString())) return false;
      if (org) {
        if (!e.isOrg) return false;
        if (_organizationId != null) {
          if (e.organizationId?.toString() != _organizationId.toString()) return false;
        }
      }
      if (!org && e.isOrg) return false;
      final t = e.authType;
      if (!_allowedAuth.contains(t)) return false;
      return true;
    }).toList();
  }

  Widget _identitiesTab() {
    final hasOrg = _organizationId != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasOrg)
            _identitySection(
              title: 'Organization identities',
              isOrg: true,
              linked: _linkedOrg(),
              available: _availableFor(true),
            ),
          _identitySection(
            title: 'Personal identities',
            isOrg: false,
            linked: _linkedPersonal(),
            available: _availableFor(false),
          ),
          _newDraftsSection(),
        ],
      ),
    );
  }

  Widget _identitySection({
    required String title,
    required bool isOrg,
    required List<ManagedIdentity> linked,
    required List<ManagedIdentity> available,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
              TextButton.icon(
                onPressed: () => _addDraft(isOrg),
                icon: Icon(AppIcons.plus, size: 16),
                label: const Text('New'),
              ),
            ],
          ),
          if (linked.isEmpty && available.isEmpty)
            Text('No identities yet', style: TextStyle(fontSize: 12, color: cs.outline)),
          for (final m in linked) _linkedIdentityCard(m),
          if (available.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Available to link (${available.length})',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.outline)),
            const SizedBox(height: 6),
            for (final m in available)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() {
                    final id = m.id is int ? m.id as int : int.tryParse(m.id.toString());
                    if (id != null && !_linkedIds.contains(id)) _linkedIds.add(id);
                  }),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Row(
                      children: [
                        Icon(AppIcons.linkVariant, size: 16, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.name.isEmpty ? 'Unnamed' : m.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text(m.username.isEmpty ? 'No username' : m.username,
                                  style: TextStyle(fontSize: 11, color: cs.outline)),
                            ],
                          ),
                        ),
                        Text(_authLabel(m.authType), style: TextStyle(fontSize: 11, color: cs.outline)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _newDraftsSection() {
    final news = _drafts.entries.where((e) => e.key.startsWith('new-')).toList();
    if (news.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final e in news) _draftCard(e.key, e.value, isOrgScope: e.value.scope == 'organization')],
    );
  }

  Future<void> _moveToOrg(ManagedIdentity m) async {
    if (_organizationId == null || m.isOrg) return;
    try {
      await ServerEditorService.moveIdentityToOrganization(
        token: widget.token,
        identityId: m.id,
        organizationId: _organizationId,
      );
      final identities = await ServerEditorService.getIdentities(widget.token);
      if (!mounted) return;
      setState(() => _allIdentities = identities);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Identity moved to organization'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Move failed: $e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Widget _linkedIdentityCard(ManagedIdentity m) {
    final cs = Theme.of(context).colorScheme;
    final draft = _drafts[m.id.toString()];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(m.name.isEmpty ? 'Unnamed' : m.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              Text(_authLabel(m.authType), style: TextStyle(fontSize: 11, color: cs.outline)),
              if (!m.isOrg && _organizationId != null)
                IconButton(
                  icon: Icon(AppIcons.brandDomain, size: 18, color: cs.primary),
                  onPressed: () => _moveToOrg(m),
                ),
              IconButton(
                icon: Icon(AppIcons.cancel, size: 18, color: cs.outline),
                onPressed: () => setState(() {
                  _linkedIds.removeWhere((id) => id.toString() == m.id.toString());
                  _drafts.remove(m.id.toString());
                }),
              ),
            ],
          ),
          if (draft != null) _draftFields(m.id.toString(), draft),
          if (draft == null)
            TextButton(
              onPressed: () => setState(() {
                _drafts[m.id.toString()] = IdentityDraft.fromManaged(m);
              }),
              child: const Text('Edit credentials'),
            ),
        ],
      ),
    );
  }

  Widget _draftCard(String key, IdentityDraft draft, {required bool isOrgScope}) {
    final cs = Theme.of(context).colorScheme;
    final isNew = key.startsWith('new-');
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isNew ? cs.primaryContainer.withValues(alpha: 0.35) : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(isNew ? 'New identity${isOrgScope ? ' (org)' : ''}' : 'Edited identity',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              if (isNew)
                IconButton(
                  icon: Icon(AppIcons.trashCanOutline, size: 18, color: cs.outline),
                  onPressed: () => setState(() => _drafts.remove(key)),
                ),
            ],
          ),
          _draftFields(key, draft),
        ],
      ),
    );
  }

  Widget _draftFields(String key, IdentityDraft draft) {
    final options = ServerEditorConstants.authTypeLabels.where((o) => _allowedAuth.contains(o['value'])).toList();
    final fallback = _allowedAuth.isNotEmpty ? _allowedAuth.first : 'password';
    final selected = options.any((o) => o['value'] == draft.authType) ? draft.authType : fallback;
    final showUser = selected != 'password-only';
    final showPassword = selected == 'password' || selected == 'password-only' || selected == 'both';
    final showKey = selected == 'ssh' || selected == 'both';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Identity name'),
        TextFormField(
          initialValue: draft.name,
          decoration: _dec('Identity name', AppIcons.accountCircleOutline),
          onChanged: (v) => draft.name = v,
        ),
        if (showUser) ...[
          _label('Username'),
          TextFormField(
            initialValue: draft.username,
            decoration: _dec('Username', AppIcons.accountCircleOutline),
            onChanged: (v) => draft.username = v,
          ),
        ],
        _label('Authentication'),
        DropdownButtonFormField<String>(
          key: ValueKey('${key}_$selected'),
          initialValue: selected,
          decoration: _dec(null, AppIcons.shieldAccountOutline),
          items: [for (final o in options) DropdownMenuItem(value: o['value'], child: Text(o['label']!))],
          onChanged: (v) {
            if (v != null) setState(() => draft.authType = v);
          },
        ),
        if (showPassword) ...[
          _label('Password'),
          TextFormField(
            initialValue: draft.password,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: _dec('Password', AppIcons.lockOutline),
            onChanged: (v) {
              draft.password = v;
              draft.passwordTouched = true;
            },
          ),
        ],
        if (showKey) ...[
          _label('SSH private key'),
          _keyPicker(key, draft),
          _label('Passphrase (optional)'),
          TextFormField(
            initialValue: draft.passphrase,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: _dec('Passphrase', AppIcons.lockOutline),
            onChanged: (v) {
              draft.passphrase = v;
              draft.passphraseTouched = true;
            },
          ),
        ],
      ],
    );
  }

  Widget _keyPicker(String key, IdentityDraft draft) {
    final cs = Theme.of(context).colorScheme;
    String? name;
    if (draft.sshKey != null && draft.sshKey!.isNotEmpty) {
      name = draft.sshKey!.length > 40 ? 'Key loaded (${draft.sshKey!.length} chars)' : 'Key loaded';
    }
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final result = await FilePicker.platform.pickFiles(withData: true);
          if (result == null || result.files.isEmpty) return;
          final file = result.files.first;
          try {
            String content;
            if (file.bytes != null) {
              content = utf8.decode(file.bytes!, allowMalformed: true);
            } else if (file.path != null) {
              content = await File(file.path!).readAsString();
            } else {
              return;
            }
            setState(() => draft.sshKey = content);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to read key: $e'), behavior: SnackBarBehavior.floating),
              );
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(AppIcons.fileUploadOutline, size: 20, color: cs.outline),
              const SizedBox(width: 12),
              Expanded(
                child: Text(name ?? 'Select key file',
                    style: TextStyle(fontSize: 14, color: name != null ? cs.onSurface : cs.outline), overflow: TextOverflow.ellipsis),
              ),
              if (name != null) Icon(AppIcons.checkCircle, size: 18, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }

  void _addDraft(bool forOrg) {
    if (forOrg && _organizationId == null) return;
    final id = 'new-${DateTime.now().millisecondsSinceEpoch}-${_drafts.length}';
    final orgId = forOrg ? _organizationId : null;
    setState(() {
      _drafts[id] = IdentityDraft(
        name: _name.text,
        authType: _allowedAuth.isNotEmpty ? _allowedAuth.first : 'password',
        scope: forOrg ? 'organization' : 'personal',
        organizationId: orgId,
      );
    });
  }

  String _authLabel(String value) {
    final hit = ServerEditorConstants.authTypeLabels.where((o) => o['value'] == value);
    if (hit.isEmpty) return value;
    return hit.first['label']!;
  }
}
