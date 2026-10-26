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
/// Mirrors the web `ScriptsMenu`: searchable list with OS compatibility
/// filtering, personal/organization/source grouping, favorites, recents, and
/// identity selection when the server has several identities.
Future<RunScriptSelection?> showRunScriptSheet(
  BuildContext context,
  Server server,
  String token, {
  required ScriptManager manager,
  int? organizationId,
  String? organizationName,
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
      organizationName: organizationName,
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
  final String? organizationName;
  final Future<String?> Function()? osNameLoader;
  final Future<List<ManagedIdentity>> Function(String token)? identitiesLoader;

  const RunScriptSheet({
    super.key,
    required this.server,
    required this.token,
    required this.manager,
    this.organizationId,
    this.organizationName,
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
  bool _includeIncompatible = false;
  int? _selectedScriptId;
  int? _selectedIdentityId;
  Map<int, ManagedIdentity> _identities = {};
  bool _identitiesLoading = false;

  bool get _needsIdentitySelection =>
      (widget.server.identities?.length ?? 0) > 1;

  bool get _osKnown => _osName != null && _osName!.isNotEmpty;

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
    setState(() {
      _initializing = true;
      _osLoading = true;
      _loadError = null;
    });

    final osFuture = _resolveOsName(
      refresh: refresh,
    ).then<String?>((value) => normalizeOsName(value)).catchError((_) => null);

    try {
      await Future.wait([
        widget.manager.ensureLoaded(widget.token, refresh: refresh),
        widget.manager.loadPreferences(),
      ]);
      final os = await osFuture;
      if (!mounted) return;
      setState(() {
        _osName = os;
        _osLoading = false;
        _initializing = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _osLoading = false;
        _initializing = false;
      });
    }
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
    includeIncompatible: _includeIncompatible,
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

  void _setCompatibleOnly(bool compatibleOnly) {
    if (!_osKnown) return;
    final selected = _selectedScript;
    setState(() {
      _includeIncompatible = !compatibleOnly;
      if (compatibleOnly && selected != null && !_isCompatible(selected)) {
        _selectedScriptId = null;
      }
    });
  }

  void _submit() {
    final script = _selectedScript;
    if (script == null) return;
    unawaited(widget.manager.recordRecent(script.id));
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
                  padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          AppIcons.codeBracesBox,
                          color: cs.onPrimaryContainer,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
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
                padding: EdgeInsets.fromLTRB(20, compact ? 0 : 6, 20, 2),
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
                    if (compact && _needsIdentitySelection) ...[
                      const SizedBox(width: 8),
                      _compactIdentityButton(cs),
                    ],
                  ],
                ),
              ),
              if (!compact && !_initializing && _loadError == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _osChip(cs),
                      FilterChip(
                        selected: _osKnown && !_includeIncompatible,
                        onSelected: _osKnown
                            ? (value) => _setCompatibleOnly(value)
                            : null,
                        label: Text(
                          _osKnown
                              ? 'Compatible only'
                              : 'All operating systems',
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: cs.outlineVariant),
                      ),
                      if (_osLoading)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: cs.outline,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Detecting OS...',
                              style: TextStyle(fontSize: 11, color: cs.outline),
                            ),
                          ],
                        ),
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

  Widget _osChip(ColorScheme cs) {
    final label = _osKnown ? _osName! : 'OS unknown';
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: math.max(120, MediaQuery.sizeOf(context).width - 80),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _osKnown ? AppIcons.laptop : AppIcons.helpCircleOutline,
              size: 13,
              color: cs.outline,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.outline,
                ),
              ),
            ),
          ],
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
              Icon(AppIcons.alertCircle, size: 32, color: cs.error),
              const SizedBox(height: 10),
              Text(
                'Failed to load scripts',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                friendlyApiError(
                  _loadError!,
                  fallback: 'Check your connection and try again.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _load(refresh: true),
                icon: const Icon(AppIcons.refresh, size: 16),
                label: const Text('Retry'),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _query.isEmpty ? AppIcons.codeBraces : AppIcons.magnify,
                size: 30,
                color: cs.outline,
              ),
              const SizedBox(height: 10),
              Text(
                !hasAny
                    ? 'No scripts available\nCreate and manage scripts in the web client.'
                    : (_query.isEmpty
                          ? 'No compatible scripts for this server'
                          : 'No scripts match your search'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: cs.outline),
              ),
              if (_query.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                  child: const Text('Clear search'),
                ),
              ] else if (hasAny && !_includeIncompatible && _osKnown) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _setCompatibleOnly(false),
                  child: const Text('Show scripts for other systems'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final entries = _entries(scripts);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry is _SectionEntry) return _sectionHeader(entry.label, cs);
        final script = (entry as _ScriptEntry).script;
        return _scriptTile(script, cs);
      },
    );
  }

  List<Object> _entries(List<Script> visible) {
    final entries = <Object>[];
    final used = <int>{};
    final byId = {for (final script in visible) script.id: script};

    final favorites = visible
        .where((s) => widget.manager.isFavorite(s.id))
        .toList();
    if (favorites.isNotEmpty) {
      entries.add(const _SectionEntry('Favorites'));
      for (final script in favorites) {
        entries.add(_ScriptEntry(script));
        used.add(script.id);
      }
    }

    final recents = <Script>[];
    for (final id in widget.manager.recentIds) {
      final script = byId[id];
      if (script != null && !used.contains(id)) {
        recents.add(script);
        used.add(id);
      }
    }
    if (recents.isNotEmpty) {
      entries.add(const _SectionEntry('Recently used'));
      for (final script in recents) {
        entries.add(_ScriptEntry(script));
      }
    }

    void addGroup(String label, Iterable<Script> scripts) {
      final group = scripts
          .where((script) => !used.contains(script.id))
          .toList(growable: false);
      if (group.isEmpty) return;
      entries.add(_SectionEntry(label));
      for (final script in group) {
        entries.add(_ScriptEntry(script));
        used.add(script.id);
      }
    }

    addGroup(
      'Personal',
      visible.where((s) => !s.isSource && s.organizationId == null),
    );
    addGroup(
      widget.organizationName?.isNotEmpty == true
          ? widget.organizationName!
          : 'Organization',
      visible.where((s) => !s.isSource && s.organizationId != null),
    );
    addGroup('Source scripts', visible.where((s) => s.isSource));
    return entries;
  }

  Widget _sectionHeader(String label, ColorScheme cs) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 14, 22, 5),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: cs.outline,
      ),
    ),
  );

  Widget _scriptTile(Script script, ColorScheme cs) {
    final selected = script.id == _selectedScriptId;
    final favorite = widget.manager.isFavorite(script.id);
    final compatible = _isCompatible(script);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.only(left: 14, right: 2),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (selected ? cs.onPrimaryContainer : cs.primary).withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              AppIcons.codeBraces,
              size: 18,
              color: selected ? cs.onPrimaryContainer : cs.primary,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  script.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? cs.onPrimaryContainer : cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (script.isSource) ...[
                const SizedBox(width: 6),
                Icon(
                  AppIcons.linkVariant,
                  size: 13,
                  color: selected
                      ? cs.onPrimaryContainer.withValues(alpha: 0.7)
                      : cs.outline,
                ),
              ],
              if (!compatible) ...[
                const SizedBox(width: 6),
                Text(
                  'Other OS',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: cs.error,
                  ),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (script.description?.isNotEmpty == true)
                Text(
                  script.description!,
                  style: TextStyle(
                    fontSize: 11,
                    color: selected
                        ? cs.onPrimaryContainer.withValues(alpha: 0.7)
                        : cs.outline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (script.osBadges.isNotEmpty) ...[
                const SizedBox(height: 3),
                Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children: [
                    for (final os in script.osBadges) _osBadge(os, selected),
                  ],
                ),
              ],
            ],
          ),
          onTap: () =>
              setState(() => _selectedScriptId = selected ? null : script.id),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => widget.manager.toggleFavorite(script.id),
                tooltip: favorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                icon: Icon(
                  favorite ? AppIcons.star : AppIcons.starOutline,
                  size: 18,
                  color: favorite
                      ? (selected ? cs.onPrimaryContainer : cs.primary)
                      : cs.outline,
                ),
              ),
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    AppIcons.checkCircle,
                    size: 18,
                    color: cs.onPrimaryContainer,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _osBadge(String os, bool selected) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: selected
            ? cs.onPrimaryContainer.withValues(alpha: 0.08)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        os,
        style: TextStyle(
          fontSize: 10,
          color: selected
              ? cs.onPrimaryContainer.withValues(alpha: 0.8)
              : cs.outline,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _compactIdentityButton(ColorScheme cs) {
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
            child: Row(
              children: [
                Icon(
                  id == selectedIdentity
                      ? AppIcons.checkCircle
                      : AppIcons.account,
                  size: 17,
                  color: id == selectedIdentity ? cs.primary : cs.outline,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _identityLabel(id),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Icon(AppIcons.account, size: 20, color: cs.primary),
      ),
    );
  }

  Widget _footer(ColorScheme cs, {required bool compact}) {
    final selected = _selectedScript;
    final wanted = widget.server.identities ?? const <int>[];
    final selectedIdentity = _selectedIdentityId ?? wanted.firstOrNull;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: EdgeInsets.fromLTRB(20, compact ? 6 : 10, 20, compact ? 8 : 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact && _needsIdentitySelection) ...[
            Row(
              children: [
                Text(
                  'Run as identity',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.outline,
                  ),
                ),
                if (_identitiesLoading) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.7,
                      color: cs.outline,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<int>(
              initialValue: selectedIdentity,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: cs.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              items: [
                for (final id in wanted)
                  DropdownMenuItem(
                    value: id,
                    child: Text(
                      _identityLabel(id),
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _selectedIdentityId = value),
            ),
            const SizedBox(height: 8),
          ],
          if (!compact) ...[
            Row(
              children: [
                Icon(
                  selected == null ? AppIcons.codeBraces : AppIcons.checkCircle,
                  size: 14,
                  color: selected == null ? cs.outline : cs.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    selected?.name ?? 'Select a script to run',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected == null
                          ? FontWeight.w400
                          : FontWeight.w600,
                      color: selected == null ? cs.outline : cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selected != null)
                  IconButton(
                    tooltip: 'Clear selection',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _selectedScriptId = null),
                    icon: const Icon(AppIcons.close, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          FilledButton.icon(
            onPressed: selected == null ? null : _submit,
            icon: const Icon(AppIcons.play, size: 18),
            label: Text(
              selected == null ? 'Run Script' : 'Run ${selected.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: compact ? 9 : 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
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

class _SectionEntry {
  final String label;
  const _SectionEntry(this.label);
}

class _ScriptEntry {
  final Script script;
  const _ScriptEntry(this.script);
}
