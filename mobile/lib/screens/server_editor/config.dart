part of '../server_editor_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ServerEditorConfig on _ServerEditorScreenState {
  List<Server> _collectSsh(List<dynamic> items) {
    final out = <Server>[];
    for (final item in items) {
      if (item is Server) {
        if (item.protocol?.toLowerCase() == 'ssh' && item.isServer) {
          out.add(item);
        }
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
    _protocol = c['protocol']?.toString().toLowerCase();
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
    if (c['enableWallpaper'] != null) {
      _enableWallpaper = c['enableWallpaper'] == true;
    }
    if (c['enableTheming'] != null) _enableTheming = c['enableTheming'] == true;
    if (c['enableFontSmoothing'] != null) {
      _enableFontSmoothing = c['enableFontSmoothing'] == true;
    }
    if (c['enableFullWindowDrag'] != null) {
      _enableFullWindowDrag = c['enableFullWindowDrag'] == true;
    }
    if (c['enableDesktopComposition'] != null) {
      _enableDesktopComposition = c['enableDesktopComposition'] == true;
    }
    if (c['enableMenuAnimations'] != null) {
      _enableMenuAnimations = c['enableMenuAnimations'] == true;
    }
    _colorDepth = _validOr(
      c['colorDepth']?.toString() ?? '',
      ServerEditorConstants.colorDepths,
      '',
    );
    _resizeMethod = _validOr(
      c['resizeMethod']?.toString() ?? 'display-update',
      ServerEditorConstants.resizeMethods,
      'display-update',
    );
    _rdpSecurity = _validOr(
      c['rdpSecurity']?.toString() ?? '',
      ServerEditorConstants.rdpSecurityMethods,
      '',
    );
    _keyboardLayout = _validOr(
      c['keyboardLayout']?.toString() ?? 'en-us-qwerty',
      ServerEditorConstants.keyboardLayouts,
      'en-us-qwerty',
    );
    _backspaceMode = _validOr(
      c['backspaceMode']?.toString() ?? 'del',
      ServerEditorConstants.backspaceModes,
      'del',
    );
    _deleteMode = _validOr(
      c['deleteMode']?.toString() ?? 'vt',
      ServerEditorConstants.deleteModes,
      'vt',
    );
    _functionKeyMode = _validOr(
      c['functionKeyMode']?.toString() ?? 'xterm',
      ServerEditorConstants.functionKeyModes,
      'xterm',
    );
    _preOrder = _validOr(c['preOrder']?.toString() ?? 'local-first', const [
      {'label': 'Local first', 'value': 'local-first'},
      {'label': 'Remote first', 'value': 'remote-first'},
    ], 'local-first');
    _afterOrder = _validOr(
      c['afterOrder']?.toString() ?? 'remote-first',
      const [
        {'label': 'Local first', 'value': 'local-first'},
        {'label': 'Remote first', 'value': 'remote-first'},
      ],
      'remote-first',
    );
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
      if (engineValue != null && engineValue.isNotEmpty) {
        config['engineId'] = engineValue;
      }
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
        const SnackBar(
          content: Text('Please fill all required fields'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_drafts.values.any((d) => d.name.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Identity names must not be empty'),
          behavior: SnackBarBehavior.floating,
        ),
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
          folderId: _folderId is int
              ? _folderId
              : int.tryParse((_folderId ?? '').toString()),
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
          SnackBar(
            content: Text(friendlyApiError(e, fallback: 'Save failed.')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
