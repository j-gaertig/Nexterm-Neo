import 'package:flutter/material.dart';

import '../../../utils/app_icons.dart';
import '../../../models/script.dart';
import '../../../services/script_service.dart';
import '../../../models/server.dart';
import '../../../models/managed_identity.dart';
import '../../../services/server_editor_service.dart';

/// Bottom sheet to pick a script to run on [server]. Returns
/// `(scriptId, scriptName, identityId)` or `null` when cancelled.
///
/// Mirrors the web `ScriptsMenu`: searchable list with OS badges, source
/// scripts marked read-only, identity selection when the server has several
/// identities. The mobile app has no server OS data, so scripts are not
/// pre-filtered by OS — badges are informational only.
Future<RunScriptSelection?> showRunScriptSheet(BuildContext context, Server server, String token) {
  return showModalBottomSheet<RunScriptSelection>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => RunScriptSheet(server: server, token: token),
  );
}

class RunScriptSelection {
  final int scriptId;
  final String scriptName;
  final int? identityId;

  const RunScriptSelection({required this.scriptId, required this.scriptName, this.identityId});
}

class RunScriptSheet extends StatefulWidget {
  final Server server;
  final String token;

  const RunScriptSheet({super.key, required this.server, required this.token});

  @override
  State<RunScriptSheet> createState() => _RunScriptSheetState();
}

class _RunScriptSheetState extends State<RunScriptSheet> {
  List<Script>? _scripts;
  String? _error;
  String _query = '';
  int? _selectedScriptId;
  int? _selectedIdentityId;

  Map<int, ManagedIdentity> _identities = {};
  bool get _needsIdentitySelection => (widget.server.identities?.length ?? 0) > 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final scripts = await ScriptService.getAllScripts(widget.token);
      scripts.sort((a, b) {
        final bySort = a.sortOrder.compareTo(b.sortOrder);
        if (bySort != 0) return bySort;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (!mounted) return;
      setState(() => _scripts = scripts);
      if (_needsIdentitySelection) await _loadIdentities();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _loadIdentities() async {
    try {
      final all = await ServerEditorService.getIdentities(widget.token);
      final wanted = widget.server.identities?.toSet() ?? {};
      if (!mounted) return;
      setState(() {
        _identities = {
          for (final identity in all)
            if (wanted.contains(_identityIdInt(identity.id))) _identityIdInt(identity.id)!: identity,
        };
      });
    } catch (_) {
      // Identity names stay unresolved; the raw ids are still selectable.
    }
  }

  int? _identityIdInt(dynamic id) => id is int ? id : int.tryParse(id.toString());

  List<Script> get _filtered {
    final scripts = _scripts ?? const <Script>[];
    return scripts.where((s) => s.matchesSearch(_query)).toList();
  }

  void _submit() {
    final script = _filtered.where((s) => s.id == _selectedScriptId).firstOrNull;
    if (script == null) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, RunScriptSelection(
      scriptId: script.id,
      scriptName: script.name,
      identityId: _selectedIdentityId ?? widget.server.identities?.firstOrNull,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          margin: const EdgeInsets.only(top: 12, bottom: 4), width: 36, height: 4,
          decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
              child: Icon(AppIcons.codeBracesBox, color: cs.onPrimaryContainer, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Run Script', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(widget.server.name, style: TextStyle(fontSize: 12, color: cs.outline), overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search scripts...',
              prefixIcon: const Icon(AppIcons.magnify, size: 20),
              filled: true,
              fillColor: cs.surfaceContainerHigh,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary, width: 1.5)),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Divider(height: 1, color: cs.outlineVariant),
        Flexible(child: _buildList(cs)),
        if (_selectedScriptId != null && _needsIdentitySelection) _identitySelector(cs),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _selectedScriptId == null ? null : _submit,
              icon: const Icon(AppIcons.connection, size: 18),
              label: const Text('Run Script'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildList(ColorScheme cs) {
    if (_scripts == null && _error == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(AppIcons.alertCircle, size: 32, color: cs.error),
          const SizedBox(height: 12),
          Text('Failed to load scripts',
              style: TextStyle(fontSize: 14, color: cs.outline)),
        ]),
      );
    }
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_query.isEmpty ? 'No scripts available' : 'No scripts match your search',
            style: TextStyle(fontSize: 14, color: cs.outline)),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: filtered.length,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemBuilder: (_, i) {
        final script = filtered[i];
        final selected = script.id == _selectedScriptId;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.only(left: 14, right: 10),
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: (selected ? cs.onPrimaryContainer : cs.primary).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(AppIcons.codeBraces, size: 18,
                  color: selected ? cs.onPrimaryContainer : cs.primary),
            ),
            title: Row(children: [
              Expanded(child: Text(script.name,
                  style: TextStyle(fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? cs.onPrimaryContainer : cs.onSurface),
                  overflow: TextOverflow.ellipsis)),
              if (script.isSource) ...[
                const SizedBox(width: 6),
                Icon(AppIcons.linkVariant, size: 13,
                    color: selected ? cs.onPrimaryContainer.withValues(alpha: 0.7) : cs.outline),
              ],
            ]),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (script.description?.isNotEmpty == true)
                Text(script.description!,
                    style: TextStyle(fontSize: 11,
                        color: selected ? cs.onPrimaryContainer.withValues(alpha: 0.7) : cs.outline),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Wrap(spacing: 4, runSpacing: 3, children: [
                for (final os in script.osBadges) _osBadge(os, selected),
              ]),
            ]),
            onTap: () => setState(() => _selectedScriptId = script.id),
            trailing: selected
                ? Icon(AppIcons.checkCircle, size: 18, color: cs.onPrimaryContainer)
                : null,
          ),
        );
      },
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
      child: Text(os, style: TextStyle(fontSize: 10,
          color: selected ? cs.onPrimaryContainer.withValues(alpha: 0.8) : cs.outline,
          fontWeight: FontWeight.w600)),
    );
  }

  Widget _identitySelector(ColorScheme cs) {
    final wanted = widget.server.identities ?? const <int>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Divider(height: 1, color: cs.outlineVariant),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
        child: Text('Run as identity',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.outline)),
      ),
      ...wanted.map((id) {
        final identity = _identities[id];
        final selected = _selectedIdentityId == id || (_selectedIdentityId == null && id == wanted.firstOrNull);
        final label = identity == null || identity.name.isEmpty
            ? ((identity != null && identity.username.isNotEmpty)
                ? identity.username
                : 'Identity #$id')
            : identity.name;
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: Icon(AppIcons.shieldAccountOutline, size: 18,
              color: selected ? cs.primary : cs.outline),
          title: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface)),
          subtitle: (identity != null && identity.username.isNotEmpty)
              ? Text(identity.username, style: TextStyle(fontSize: 11, color: cs.outline))
              : null,
          trailing: selected ? Icon(AppIcons.checkCircle, size: 16, color: cs.primary) : null,
          onTap: () => setState(() => _selectedIdentityId = id),
        );
      }),
    ]);
  }
}
