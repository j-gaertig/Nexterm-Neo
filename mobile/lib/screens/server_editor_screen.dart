import '../widgets/app_ui.dart';
import '../utils/api_exception.dart';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/floating_navigation_bar.dart';
import '../models/managed_identity.dart';
import '../models/server.dart';
import '../models/server_details.dart';
import '../services/server_editor_service.dart';
import '../services/server_service.dart';
import '../utils/app_icons.dart';
import '../utils/server_field_config.dart';

part 'server_editor/config.dart';
part 'server_editor/sections.dart';
part 'server_editor/identities.dart';

class FolderOption {
  final dynamic id;
  final String name;
  final String type;
  final dynamic organizationId;
  const FolderOption({
    this.id,
    required this.name,
    this.type = 'folder',
    this.organizationId,
  });
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

class _ServerEditorScreenState extends State<ServerEditorScreen>
    with TickerProviderStateMixin {
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
  final Map<String, IdentityDraft> _drafts = {};
  List<ManagedIdentity> _allIdentities = [];

  bool get _isEdit => widget.editServerId != null;
  ServerFieldConfig get _fieldConfig =>
      getServerFieldConfig('server', _protocol);
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
        draft.authType = _allowedAuth.isNotEmpty
            ? _allowedAuth.first
            : 'password';
      }
    }
  }

  void _syncIconCustom() {
    final text = _icon ?? '';
    if (_iconCustom.text != text) {
      _iconCustom.text = text;
      _iconCustom.selection = TextSelection.fromPosition(
        TextPosition(offset: _iconCustom.text.length),
      );
    }
  }

  String _validOr(
    String value,
    List<Map<String, String>> options,
    String fallback,
  ) {
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
      items.add(
        DropdownMenuItem(
          value: _protocol,
          child: Text(_protocol!.toUpperCase()),
        ),
      );
    }
    return items;
  }

  void _onProtocolChanged(String? value) {
    final old = _protocol;
    setState(() {
      _protocol = value;
      if (value != null) {
        final oldDefault = old == null
            ? ''
            : (ServerEditorConstants.defaultPorts[old] ?? '');
        if (_port.text.isEmpty ||
            (_port.text == oldDefault && oldDefault.isNotEmpty)) {
          _port.text = ServerEditorConstants.defaultPorts[value] ?? _port.text;
        }
      }
      if (value != null &&
          (_icon == null ||
              ServerEditorConstants.protocolIcons.containsValue(_icon))) {
        _icon = ServerEditorConstants.protocolIcons[value];
        _syncIconCustom();
      }
      if (!_fieldConfig.showIdentities) {
        _linkedIds = [];
        _drafts.clear();
      } else {
        _linkedIds = _linkedIds.where((id) {
          final matches = _allIdentities.where(
            (e) => e.id.toString() == id.toString(),
          );
          if (matches.isEmpty) return true;
          return _allowedAuth.contains(matches.first.authType);
        }).toList();
        _drafts.removeWhere(
          (key, draft) => !_allowedAuth.contains(draft.authType),
        );
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
        final details = await ServerEditorService.getEntry(
          widget.token,
          widget.editServerId,
        );
        if (!mounted) return;
        _applyDetails(details);
        _sshCandidates = sshCandidates
            .where((s) => s.id.toString() != widget.editServerId.toString())
            .toList();
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = _isEdit
        ? 'Edit server'
        : (_protocol == null || _protocol!.isEmpty)
        ? 'New server'
        : 'New ${_protocol!.toUpperCase()} server';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppSubPageHeader(
              title: title,
              subtitle: _name.text.trim().isEmpty ? null : _name.text.trim(),
              trailing: _loading || _error != null
                  ? null
                  : FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(AppIcons.contentSave, size: 18),
                      label: const Text('Save'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.control),
                        ),
                      ),
                    ),
            ),
            if (!_loading && _error == null && _tabKeys.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadii.control),
                    border: Border.all(color: appBorderColor(cs)),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: TabBar(
                    controller: _tabs,
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadii.tile - 2),
                    ),
                    labelColor: cs.onPrimaryContainer,
                    unselectedLabelColor: cs.outline,
                    labelStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                    splashBorderRadius: BorderRadius.circular(AppRadii.tile),
                    tabs: [
                      for (final k in _tabKeys)
                        Tab(height: 38, text: _tabLabel(k)),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? AppErrorState(
                      message: _error!,
                      title: 'Could not open the server',
                    )
                  : TabBarView(
                      controller: _tabs,
                      children: [for (final k in _tabKeys) _tabView(k)],
                    ),
            ),
          ],
        ),
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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: appBorderSide(cs),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: appBorderSide(cs),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 1.5),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 2, top: 14),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.outline,
      ),
    ),
  );

  bool get _engineOffline {
    if (_engineId == null || _engineId!.isEmpty) return false;
    if (_engines.isEmpty) return true;
    final match = _engines.where((e) => e.id?.toString() == _engineId);
    if (match.isEmpty) return true;
    return !match.first.connected;
  }
}
