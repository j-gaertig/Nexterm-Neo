part of '../server_editor_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ServerEditorSections on _ServerEditorScreenState {
  Widget _detailsTab() {
    final cs = Theme.of(context).colorScheme;
    final fc = _fieldConfig;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        32 + FloatingNavigationBarInset.of(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isEdit && _organizationId != null && _folderId == null) ...[
            _label('Location'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: appBorderColor(cs)),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.brandDomain, size: 20, color: cs.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Organization server',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!_isEdit &&
              !(_organizationId != null && _folderId == null) &&
              widget.folderOptions.isNotEmpty) ...[
            _label('Folder'),
            DropdownButtonFormField<String?>(
              initialValue: _folderId?.toString(),
              decoration: _dec(null, AppIcons.brandFolder),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Root'),
                ),
                for (final f in widget.folderOptions)
                  DropdownMenuItem<String?>(
                    value: f.id?.toString(),
                    child: Text(f.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) {
                setState(() {
                  _folderId = v == null ? null : int.tryParse(v) ?? v;
                  if (v == null) {
                    _organizationId = null;
                  } else {
                    final match = widget.folderOptions.where(
                      (f) => f.id?.toString() == v,
                    );
                    _organizationId = match.isEmpty
                        ? null
                        : match.first.organizationId;
                  }
                });
              },
            ),
          ],
          _label('Name'),
          TextField(
            controller: _name,
            decoration: _dec('Server name', AppIcons.pencilOutline),
            textCapitalization: TextCapitalization.words,
          ),
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
                      color: _icon == iconName
                          ? cs.primaryContainer
                          : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: _icon == iconName
                          ? Border.all(color: cs.primary, width: 1.5)
                          : null,
                    ),
                    child: Icon(
                      AppIcons.resolveBackendIcon(_iconKey(iconName)) ??
                          AppIcons.brandServer,
                      size: 20,
                      color: _icon == iconName
                          ? cs.onPrimaryContainer
                          : cs.outline,
                    ),
                  ),
                ),
            ],
          ),
          _label('Custom icon name (e.g. mdiServer, mdiConsole)'),
          TextField(
            controller: _iconCustom,
            decoration: _dec('mdiServer', AppIcons.pencilOutline),
            onChanged: (v) =>
                setState(() => _icon = v.trim().isEmpty ? null : v.trim()),
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
                    child: Text(
                      e.connected ? e.name : '${e.name} (offline)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
                      TextField(
                        controller: _ip,
                        decoration: _dec(
                          '192.168.1.10',
                          AppIcons.serverNetwork,
                        ),
                        keyboardType: TextInputType.text,
                      ),
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
                      TextField(
                        controller: _port,
                        decoration: _dec('22', AppIcons.connection),
                        keyboardType: TextInputType.number,
                      ),
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
              TextField(
                controller: _mac,
                decoration: _dec('AA:BB:CC:DD:EE:FF', AppIcons.serverNetwork),
              ),
              _label('WoL broadcast address'),
              TextField(
                controller: _wolBroadcast,
                decoration: _dec('192.168.1.255', AppIcons.serverNetwork),
              ),
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
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        32 + FloatingNavigationBarInset.of(context),
      ),
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
              onSwap: () => setState(
                () => _preOrder = _preOrder == 'local-first'
                    ? 'remote-first'
                    : 'local-first',
              ),
            ),
            _hookGroup(
              title: 'After disconnect',
              localController: _afterLocal,
              remoteController: _afterRemote,
              order: _afterOrder,
              onSwap: () => setState(
                () => _afterOrder = _afterOrder == 'local-first'
                    ? 'remote-first'
                    : 'local-first',
              ),
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
            _optionDropdown(
              ServerEditorConstants.backspaceModes,
              _backspaceMode,
              (v) => setState(() => _backspaceMode = v),
            ),
            _label('Terminal delete'),
            _optionDropdown(
              ServerEditorConstants.deleteModes,
              _deleteMode,
              (v) => setState(() => _deleteMode = v),
            ),
            _label('Function keys'),
            _optionDropdown(
              ServerEditorConstants.functionKeyModes,
              _functionKeyMode,
              (v) => setState(() => _functionKeyMode = v),
            ),
          ],
          if (fc.showRdpSecurity) ...[
            _label('RDP security'),
            _optionDropdown(
              ServerEditorConstants.rdpSecurityMethods,
              _rdpSecurity,
              (v) => setState(() => _rdpSecurity = v),
            ),
          ],
          if (fc.showKeyboardLayout) ...[
            _label('Keyboard layout'),
            DropdownButtonFormField<String>(
              initialValue:
                  ServerEditorConstants.keyboardLayouts.any(
                    (k) => k['value'] == _keyboardLayout,
                  )
                  ? _keyboardLayout
                  : 'en-us-qwerty',
              decoration: _dec(null, AppIcons.keyboard),
              items: [
                for (final k in ServerEditorConstants.keyboardLayouts)
                  DropdownMenuItem(
                    value: k['value'],
                    child: Text(k['label']!, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _keyboardLayout = v);
              },
            ),
          ],
          if (fc.showDisplaySettings) ...[
            _label('Color depth'),
            _optionDropdown(
              ServerEditorConstants.colorDepths,
              _colorDepth,
              (v) => setState(() => _colorDepth = v),
            ),
            _label('Resize method'),
            _optionDropdown(
              ServerEditorConstants.resizeMethods,
              _resizeMethod,
              (v) => setState(() => _resizeMethod = v),
            ),
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
              title: 'Wallpaper',
              subtitle: 'Show desktop wallpaper',
              icon: AppIcons.palette,
              value: _enableWallpaper,
              onChanged: (v) => setState(() => _enableWallpaper = v),
            ),
            _switchTile(
              title: 'Theming',
              subtitle: 'Allow visual styles',
              icon: AppIcons.palette,
              value: _enableTheming,
              onChanged: (v) => setState(() => _enableTheming = v),
            ),
            _switchTile(
              title: 'Font smoothing',
              subtitle: 'Smooth fonts in session',
              icon: AppIcons.formatSize,
              value: _enableFontSmoothing,
              onChanged: (v) => setState(() => _enableFontSmoothing = v),
            ),
            _switchTile(
              title: 'Full window drag',
              subtitle: 'Show contents while dragging',
              icon: AppIcons.cursorDefaultClick,
              value: _enableFullWindowDrag,
              onChanged: (v) => setState(() => _enableFullWindowDrag = v),
            ),
            _switchTile(
              title: 'Desktop composition',
              subtitle: 'Enable composition effects',
              icon: AppIcons.monitorMultiple,
              value: _enableDesktopComposition,
              onChanged: (v) => setState(() => _enableDesktopComposition = v),
            ),
            _switchTile(
              title: 'Menu animations',
              subtitle: 'Animate menus and windows',
              icon: AppIcons.creation,
              value: _enableMenuAnimations,
              onChanged: (v) => setState(() => _enableMenuAnimations = v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _optionDropdown(
    List<Map<String, String>> options,
    String value,
    ValueChanged<String> onChanged,
  ) {
    final valid = options.any((o) => o['value'] == value)
        ? value
        : (options.isNotEmpty ? options.first['value']! : '');
    return DropdownButtonFormField<String>(
      initialValue: valid,
      decoration: _dec(null, AppIcons.cogOutline),
      items: [
        for (final o in options)
          DropdownMenuItem(
            value: o['value'],
            child: Text(o['label']!, overflow: TextOverflow.ellipsis),
          ),
      ],
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
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: appBorderColor(cs)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
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
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: appBorderColor(cs)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.serverNetwork, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              const Text(
                'Jump hosts',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Text(
            'Route SSH through other servers in order',
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
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
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _jumpHostValue(i),
                      decoration: _dec(null, AppIcons.server),
                      items: [
                        for (final s in _availableJumpHosts(i))
                          DropdownMenuItem(
                            value: s.id.toString(),
                            child: Text(
                              '${s.name} (${s.ip})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (_jumpHosts[i] != null &&
                            !_availableJumpHosts(i).any(
                              (s) =>
                                  s.id.toString() == _jumpHosts[i].toString(),
                            ))
                          DropdownMenuItem(
                            value: _jumpHosts[i].toString(),
                            child: Text(
                              'Server ${_jumpHosts[i]} (unavailable)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
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
              _sshCandidates.isEmpty
                  ? 'No SSH servers available'
                  : 'All SSH servers already added',
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
    return _sshCandidates
        .where((s) => !selected.contains(s.id.toString()))
        .toList();
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
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: appBorderColor(cs)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: onSwap,
                icon: Icon(AppIcons.refresh, size: 18, color: cs.primary),
              ),
            ],
          ),
          _hookField(
            label: firstIsLocal ? 'Local (1st)' : 'Remote (1st)',
            controller: firstIsLocal ? localController : remoteController,
          ),
          const SizedBox(height: 8),
          _hookField(
            label: firstIsLocal ? 'Remote (2nd)' : 'Local (2nd)',
            controller: firstIsLocal ? remoteController : localController,
          ),
          if (_engineOffline)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Selected engine is offline, remote hooks run on fallback engine',
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ),
        ],
      ),
    );
  }

  Widget _hookField({
    required String label,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLength: 2000,
          decoration: _dec('command', AppIcons.consoleLine),
        ),
      ],
    );
  }
}
