import 'package:flutter/material.dart';

import '../../api/nexterm_api.dart';
import '../../snippets/snippet_models.dart';

/// Bundled snippets + scripts for the More page (test seam).
class MoreData {
  const MoreData({required this.snippets, required this.scripts});

  final List<Snippet> snippets;
  final List<ScriptEntry> scripts;
}

/// More page: snippet library (view/create/delete) + script library.
class MorePage extends StatefulWidget {
  const MorePage(
      {super.key, required this.api, required this.token, this.loader, this.onSessionExpired});

  final NextermApi api;
  final String token;

  /// Called on HTTP 401 so expired sessions return to login.
  final VoidCallback? onSessionExpired;

  /// Test seam (defaults to live `GET /api/snippets/all` + scripts).
  final Future<MoreData> Function()? loader;

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  MoreData? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<MoreData> _defaultLoad() async {
    final snippets = await widget.api.fetchSnippets(widget.token);
    final scripts = await widget.api.fetchScripts(widget.token);
    return MoreData(
      snippets: snippets
          .map((m) {
            try {
              return Snippet.fromJson(m);
            } catch (_) {
              return null;
            }
          })
          .whereType<Snippet>()
          .toList(),
      scripts: scripts
          .map((m) {
            try {
              return ScriptEntry.fromJson(m);
            } catch (_) {
              return null;
            }
          })
          .whereType<ScriptEntry>()
          .toList(),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await (widget.loader?.call() ?? _defaultLoad());
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on SessionExpiredException {
      if (!mounted) return;
      widget.onSessionExpired?.call();
      return;
    } on NextermApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load library.';
        _loading = false;
      });
    }
  }

  Future<void> _deleteSnippet(Snippet snippet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete snippet?'),
        content: Text('"${snippet.name}" will be deleted. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.deleteSnippet(
          widget.token, snippet.id, snippet.organizationId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Snippet deleted.')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e is NextermApiException
                  ? e.message
                  : 'Delete failed.')),
        );
      }
    }
  }

  Future<void> _deleteScript(ScriptEntry script) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete script?'),
        content:
            Text('"${script.name}" will be deleted. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.deleteScript(widget.token, script.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Script deleted.')),
        );
      }
      await _load();
    } on SessionExpiredException {
      widget.onSessionExpired?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e is NextermApiException
                  ? e.message
                  : 'Delete failed.')),
        );
      }
    }
  }

  Future<void> _createScript() async {
    final saved = await _openScriptEditor();
    if (saved == true) await _load();
  }

  Future<void> _editScript(ScriptEntry script) async {
    ScriptEntry full = script;
    if (script.content == null && mounted) {
      try {
        final detail =
            await widget.api.fetchScript(widget.token, script.id);
        full = ScriptEntry.fromJson({...detail, 'id': script.id});
      } on SessionExpiredException {
        widget.onSessionExpired?.call();
        return;
      } catch (_) {
        // Edit with list-level fields only.
      }
    }
    if (!mounted) return;
    final saved = await _openScriptEditor(existing: full);
    if (saved == true) await _load();
  }

  /// Script editor (web ScriptDialog equivalent).
  Future<bool?> _openScriptEditor({ScriptEntry? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final content =
        TextEditingController(text: existing?.content ?? '');
    final description =
        TextEditingController(text: existing?.description ?? '');
    final osFilter = TextEditingController();
    String? error;
    try {
      return await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            title: Text(existing == null
                ? 'New script'
                : 'Edit script'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: content,
                    decoration: const InputDecoration(
                        labelText: 'Content',
                        border: OutlineInputBorder()),
                    maxLines: 8,
                    keyboardType: TextInputType.multiline,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: osFilter,
                    decoration: const InputDecoration(
                        labelText: 'OS filter (optional, comma separated)',
                        hintText: 'linux, windows',
                        border: OutlineInputBorder()),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!,
                        style: TextStyle(
                            color: Theme.of(ctx)
                                .colorScheme
                                .error,
                            fontSize: 12)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (name.text.trim().isEmpty ||
                      content.text.trim().isEmpty) {
                    setDialog(() => error =
                        'Name and content are required.');
                    return;
                  }
                  final payload = <String, dynamic>{
                    'name': name.text.trim(),
                    'content': content.text,
                    if (description.text.trim().isNotEmpty)
                      'description':
                          description.text.trim(),
                    if (osFilter.text.trim().isNotEmpty)
                      'osFilter': osFilter.text
                          .split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList(),
                  };
                  try {
                    if (existing == null) {
                      await widget.api.createScript(
                          widget.token, payload);
                    } else {
                      await widget.api.updateScript(
                          widget.token,
                          existing.id,
                          payload);
                    }
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } on SessionExpiredException {
                    widget.onSessionExpired?.call();
                  } on NextermApiException catch (e) {
                    setDialog(() => error = e.message);
                  } catch (_) {
                    setDialog(
                        () => error = 'Save failed.');
                  }
                },
                child: Text(
                    existing == null ? 'Create' : 'Save'),
              ),
            ],
          ),
        ),
      );
    } finally {
      name.dispose();
      content.dispose();
      description.dispose();
      osFilter.dispose();
    }
  }

  Future<void> _createSnippet() async {
    final saved = await _openSnippetEditor();
    if (saved == true) await _load();
  }

  Future<void> _editSnippet(Snippet snippet) async {
    final saved = await _openSnippetEditor(existing: snippet);
    if (saved == true) await _load();
  }

  /// Snippet editor (web SnippetDialog equivalent): name/command plus
  /// description and OS filter. Organization snippets keep their scope
  /// (edit/delete pass `organizationId`).
  Future<bool?> _openSnippetEditor({Snippet? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final command =
        TextEditingController(text: existing?.command ?? '');
    final description =
        TextEditingController(text: existing?.description ?? '');
    final osFilter = TextEditingController(
        text: (existing?.osFilter ?? const []).join(', '));
    String? error;
    try {
      return await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            title: Text(existing == null
                ? 'New snippet'
                : 'Edit snippet'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: command,
                    decoration: const InputDecoration(
                        labelText: 'Command',
                        border: OutlineInputBorder()),
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: osFilter,
                    decoration: const InputDecoration(
                        labelText: 'OS filter (optional, comma separated)',
                        hintText: 'linux, windows',
                        border: OutlineInputBorder()),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!,
                        style: TextStyle(
                            color: Theme.of(ctx)
                                .colorScheme
                                .error,
                            fontSize: 12)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (name.text.trim().isEmpty ||
                      command.text.trim().isEmpty) {
                    setDialog(() => error =
                        'Name and command are required.');
                    return;
                  }
                  final filter = osFilter.text
                      .split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList();
                  final payload = <String, dynamic>{
                    'name': name.text.trim(),
                    'command': command.text.trim(),
                    if (description.text.trim().isNotEmpty)
                      'description': description.text.trim(),
                    if (filter.isNotEmpty) 'osFilter': filter,
                  };
                  try {
                    if (existing == null) {
                      await widget.api.createSnippet(
                          widget.token, payload);
                    } else {
                      await widget.api.updateSnippet(
                        widget.token,
                        existing.id,
                        payload,
                        organizationId:
                            existing.organizationId,
                      );
                    }
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } on SessionExpiredException {
                    widget.onSessionExpired?.call();
                  } on NextermApiException catch (e) {
                    setDialog(() => error = e.message);
                  } catch (_) {
                    setDialog(
                        () => error = 'Save failed.');
                  }
                },
                child: Text(
                    existing == null ? 'Create' : 'Save'),
              ),
            ],
          ),
        ),
      );
    } finally {
      name.dispose();
      command.dispose();
      description.dispose();
      osFilter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _data == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null && _data == null
                ? ListView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 64),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: _load,
                          child: const Text('Retry')),
                    ],
                  )
                : ListView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    padding:
                        const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      _SectionHeader(
                        title:
                            'Snippets (${_data?.snippets.length ?? 0})',
                        actionLabel: 'New',
                        onAction: _createSnippet,
                      ),
                      if ((_data?.snippets ?? const []).isEmpty)
                        const _EmptyNote(
                            text: 'No snippets yet.')
                      else
                        for (final snippet in _data!.snippets)
                          _SnippetTile(
                            snippet: snippet,
                            onEdit: () =>
                                _editSnippet(snippet),
                            onDelete: () =>
                                _deleteSnippet(snippet),
                          ),
                      const SizedBox(height: 16),
                      _SectionHeader(
                        title:
                            'Scripts (${_data?.scripts.length ?? 0})',
                        actionLabel: 'New',
                        onAction: _createScript,
                      ),
                      if ((_data?.scripts ?? const []).isEmpty)
                        const _EmptyNote(
                            text: 'No scripts yet.')
                      else
                        for (final script in _data!.scripts)
                          Card(
                            elevation: 0,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHigh,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(16)),
                            child: ListTile(
                              leading: const Icon(
                                  Icons.code),
                              title: Text(script.name,
                                  style: const TextStyle(
                                      fontWeight:
                                          FontWeight.w600)),
                              subtitle: script.description !=
                                          null &&
                                      script.description!
                                          .isNotEmpty
                                  ? Text(
                                      script.description!,
                                      maxLines: 1,
                                      overflow: TextOverflow
                                          .ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12))
                                  : null,
                              trailing: PopupMenuButton<String>(
                                icon: const Icon(
                                    Icons.more_vert),
                                tooltip: 'Script actions',
                                onSelected: (v) {
                                  if (v == 'edit') {
                                    _editScript(script);
                                  } else if (v ==
                                      'delete') {
                                    _deleteScript(script);
                                  }
                                },
                                itemBuilder: (_) =>
                                    const [
                                  PopupMenuItem(
                                      value: 'edit',
                                      child:
                                          Text('Edit')),
                                  PopupMenuItem(
                                      value: 'delete',
                                      child:
                                          Text('Delete')),
                                ],
                              ),
                              onTap: () =>
                                  _editScript(script),
                            ),
                          ),
                    ],
                  ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.title,
      required this.actionLabel,
      required this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          if (actionLabel != null)
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add, size: 18),
              label: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant)),
    );
  }
}

class _SnippetTile extends StatelessWidget {
  const _SnippetTile(
      {required this.snippet,
      required this.onEdit,
      required this.onDelete});

  final Snippet snippet;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHigh,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.text_snippet,
              color: cs.onPrimaryContainer, size: 18),
        ),
        title: Text(snippet.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: snippet.description != null &&
                snippet.description!.isNotEmpty
            ? Text(snippet.description!,
                maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(snippet.command,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 13)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                  ),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: Icon(Icons.delete,
                        size: 18, color: cs.error),
                    label: Text('Delete',
                        style: TextStyle(color: cs.error)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
