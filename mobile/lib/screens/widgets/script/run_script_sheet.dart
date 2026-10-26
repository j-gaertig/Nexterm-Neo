import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/managed_identity.dart';
import '../../../models/script.dart';
import '../../../models/server.dart';
import '../../../services/script_manager.dart';
import '../../../services/server_editor_service.dart';
import '../../../utils/api_exception.dart';
import '../../../utils/app_icons.dart';

/// Bottom sheet to pick a script to run on [server]. Returns
/// `(scriptId, scriptName, identityId)` or `null` when cancelled.
///
/// All scripts available to the server are listed in one flat list. The
/// optional compatibility filter is controlled by the icon button next to the
/// search field. When the server has several identities, the identity picker
/// lives in the same row so the footer can stay focused on the single action
/// that matters: running the selected script.
Future<RunScriptSelection?> showRunScriptSheet(
  BuildContext context,
  Server server,
  String token, {
  required ScriptManager manager,
  int? organizationId,
  Future<String?> Function()? osNameLoader,
  Future<List<ManagedIdentity>> Function(String token)? identitiesLoader,
}) {
  return showModalBottomSheet<RunScriptSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => RunScriptSheet(
      server: server,
      token: token,
      manager: manager,
      organizationId: organizationId,
      osNameLoader: osNameLoader,
      identitiesLoader: identitiesLoader,
    ),
  );
}

class RunScriptSelection {
  final int scriptId;
  final String scriptName;
  final int? identityId;

  const RunScriptSelection({
    required this.scriptId,
    required this.scriptName,
    this.identityId,
  });
}

class RunScriptSheet extends StatefulWidget {
  final Server server;
  final String token;
  final ScriptManager manager;
  final int? organizationId;
  final Future<String?> Function()? osNameLoader;
  final Future<List<ManagedIdentity>> Function(String token)? identitiesLoader;

  const RunScriptSheet({
    super.key,
    required this.server,
    required this.token,
    required this.manager,
    this.organizationId,
    this.osNameLoader,
    this.identitiesLoader,
  });

  @override
  State<RunScriptSheet> createState() => _RunScriptSheetState();
}

class _RunScriptSheetState extends State<RunScriptSheet> {
  final _searchController = TextEditingController();
  Object? _loadError;
  String _query = '';
  String? _osName;
  bool _osLoading = true;
  bool _initializing = true;
  bool _compatibleOnly = false;
  int? _selectedScriptId;
  int? _selectedIdentityId;
  Map<int, ManagedIdentity> _identities = {};
  bool _identitiesLoading = false;

  bool get _needsIdentitySelection =>
      (widget.server.identities?.length ?? 0) > 1;

  bool get _osKnown => _osName != null && _osName!.isNotEmpty;

  bool get _compatibilityFilterActive => _osKnown && _compatibleOnly;

  String get _compatibilityTooltip {
    if (_osLoading) return 'Detecting operating system';
    if (!_osKnown) return 'Operating system unknown';
    return _compatibleOnly ? 'Show all scripts' : 'Compatible only';
  }

  @override
  void initState() {
    super.initState();
    _selectedIdentityId = widget.server.identities?.firstOrNull;
    widget.manager.addListener(_onManagerChanged);
    _load();
    if (_needsIdentitySelection) _loadIdentities();
  }

  @override
  void dispose() {
    widget.manager.removeListener(_onManagerChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onManagerChanged() {
    if (mounted) setState(() {});
  }

  Future<String?> _resolveOsName({bool refresh = false}) async {
    try {
      final raw =
          widget.osNameLoader?.call() ??
          widget.manager.serverOsName(
            widget.server,
            widget.token,
            refresh: refresh,
          );
      return await raw.timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (mounted) {
      setState(() {
        _initializing = true;
        _osLoading = true;
        _loadError = null;
      });
    }

    final osFuture = _resolveOsName(
      refresh: refresh,
    ).then<String?>((value) => normalizeOsName(value)).catchError((_) => null);

    try {
      // The catalogue is the only blocking load. OS detection happens in the
      // background so the list can appear as soon as the scripts are ready.
      await widget.manager.ensureLoaded(widget.token, refresh: refresh);
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _initializing = false;
      });
    }

    final os = await osFuture;
    if (!mounted) return;
    setState(() {
      _osName = os;
      _osLoading = false;
      if (!_osKnown) _compatibleOnly = false;
      final selected = _selectedScript;
      if (_compatibleOnly && selected != null && !_isCompatible(selected)) {
        _selectedScriptId = null;
      }
    });
  }

  Future<void> _loadIdentities() async {
    setState(() => _identitiesLoading = true);
    try {
      final loader =
          widget.identitiesLoader ?? ServerEditorService.getIdentities;
      final all = await loader(widget.token);
      final wanted = widget.server.identities?.toSet() ?? {};
      if (!mounted) return;
      setState(() {
        _identities = {
          for (final identity in all)
            if (wanted.contains(_identityIdInt(identity.id)))
              _identityIdInt(identity.id)!: identity,
        };
        _identitiesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _identitiesLoading = false);
    }
  }

  int? _identityIdInt(dynamic id) =>
      id is int ? id : int.tryParse(id.toString());

  List<Script> get _visibleScripts => widget.manager.scriptsForServer(
    organizationId: widget.organizationId,
    serverOsName: _osName,
    includeIncompatible: !_compatibilityFilterActive,
    query: _query,
  );

  Script? get _selectedScript {
    final id = _selectedScriptId;
    if (id == null) return null;
    return widget.manager.scriptById(id);
  }

  bool _isCompatible(Script script) {
    if (!_osKnown) return true;
    return matchesOsFilter(script.osFilter, _osName, isPveEntry: false);
  }

  void _toggleCompatibilityFilter() {
    if (!_osKnown) return;
    final selected = _selectedScript;
    setState(() {
      _compatibleOnly = !_compatibleOnly;
      if (_compatibleOnly && selected != null && !_isCompatible(selected)) {
        _selectedScriptId = null;
      }
    });
  }

  void _submit() {
    final script = _selectedScript;
    if (script == null) return;
    Navigator.pop(
      context,
      RunScriptSelection(
        scriptId: script.id,
        scriptName: script.name,
        identityId:
            _selectedIdentityId ?? widget.server.identities?.firstOrNull,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    final availableHeight = math.max(
      0.0,
      media.size.height - media.viewInsets.bottom,
    );
    // The keyboard padding and the sheet height are additive. Keep the sheet
    // inside the space above the keyboard and drop non-essential chrome when
    // that space gets tight (small phones with a keyboard open).
    final sheetHeight = math.min(media.size.height * 0.9, availableHeight);
    final compact = availableHeight < 380;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: sheetHeight,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!compact) ...[
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Run Script',
                              style: tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              widget.server.name,
                              style: TextStyle(fontSize: 12, color: cs.outline),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Close',
                        icon: const Icon(AppIcons.close, size: 20),
                      ),
                    ],
                  ),
                ),
              ] else
                const SizedBox(height: 6),
              if (widget.manager.isLoading)
                const LinearProgressIndicator(minHeight: 2),
              Padding(
                padding: EdgeInsets.fromLTRB(20, compact ? 0 : 6, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search scripts...',
                          prefixIcon: const Icon(AppIcons.magnify, size: 20),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(AppIcons.close, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          filled: true,
                          fillColor: cs.surfaceContainerHigh,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: cs.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _compatibilityButton(cs),
                    if (_needsIdentitySelection) ...[
                      const SizedBox(width: 8),
                      _identityButton(cs),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              Expanded(child: _buildBody(cs)),
              _footer(cs, compact: compact),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compatibilityButton(ColorScheme cs) {
    final active = _compatibilityFilterActive;
    final enabled = _osKnown && !_osLoading;
    final background = active
        ? cs.primary
        : (enabled ? cs.surfaceContainerHigh : cs.surfaceContainerLow);
    final foreground = active
        ? cs.onPrimary
        : (enabled ? cs.onSurfaceVariant : cs.outline);

    return Tooltip(
      message: _compatibilityTooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        toggled: active,
        label: _compatibilityTooltip,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? _toggleCompatibilityFilter : null,
            child: SizedBox.square(
              dimension: 48,
              child: Center(
                child: _osLoading
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      )
                    : Icon(AppIcons.filterVariant, size: 20, color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _identityButton(ColorScheme cs) {
    final wanted = widget.server.identities ?? const <int>[];
    final selectedIdentity = _selectedIdentityId ?? wanted.firstOrNull;

    return PopupMenuButton<int>(
      tooltip: 'Run as identity',
      initialValue: selectedIdentity,
      onSelected: (value) => setState(() => _selectedIdentityId = value),
      itemBuilder: (context) => [
        for (final id in wanted)
          PopupMenuItem(
            value: id,
            child: Text(
              _identityLabel(id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: id == selectedIdentity
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: id == selectedIdentity ? cs.primary : cs.onSurface,
              ),
            ),
          ),
      ],
      child: SizedBox.square(
        dimension: 48,
        child: Material(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(AppIcons.account, size: 20),
              if (_identitiesLoading)
                const Positioned(
                  right: 7,
                  bottom: 7,
                  child: SizedBox.square(
                    dimension: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Failed to load scripts',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                friendlyApiError(
                  _loadError!,
                  fallback: 'Check your connection and try again.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _load(refresh: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final scripts = _visibleScripts;
    if (scripts.isEmpty) {
      final hasAny = widget.manager
          .scriptsForServer(
            organizationId: widget.organizationId,
            serverOsName: null,
            includeIncompatible: true,
          )
          .isNotEmpty;
      final filteredByCompatibility =
          hasAny && _compatibilityFilterActive && _query.isEmpty;

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                !hasAny
                    ? 'No scripts available'
                    : (_query.isEmpty
                          ? 'No compatible scripts for this server'
                          : 'No scripts match your search'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              if (!hasAny) ...[
                const SizedBox(height: 6),
                Text(
                  'Create and manage scripts in the web client.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ],
              if (_query.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                  child: const Text('Clear search'),
                ),
              ] else if (filteredByCompatibility) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _toggleCompatibilityFilter,
                  child: const Text('Show all scripts'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      itemCount: scripts.length,
      itemBuilder: (context, index) => _scriptTile(scripts[index], cs),
    );
  }

  Widget _scriptTile(Script script, ColorScheme cs) {
    final selected = script.id == _selectedScriptId;
    final description = script.description?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? cs.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          selected: selected,
          child: InkWell(
            key: ValueKey('script-${script.id}'),
            onTap: () => setState(() => _selectedScriptId = script.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    script.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? cs.onPrimary : cs.onSurface,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: selected
                            ? cs.onPrimary.withValues(alpha: 0.78)
                            : cs.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(ColorScheme cs, {required bool compact}) {
    final selected = _selectedScript;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: EdgeInsets.fromLTRB(20, compact ? 8 : 10, 20, compact ? 8 : 12),
      child: FilledButton(
        key: const ValueKey('run-script-button'),
        onPressed: selected == null ? null : _submit,
        style: FilledButton.styleFrom(
          minimumSize: Size.fromHeight(compact ? 46 : 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          'Run',
          maxLines: 1,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  String _identityLabel(int id) {
    final identity = _identities[id];
    if (identity == null) return 'Identity #$id';
    if (identity.name.trim().isNotEmpty) return identity.name;
    if (identity.username.trim().isNotEmpty) return identity.username;
    return 'Identity #$id';
  }
}
