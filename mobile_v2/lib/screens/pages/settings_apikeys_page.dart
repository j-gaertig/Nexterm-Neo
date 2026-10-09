import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/nexterm_api.dart';
import '../../settings/settings_widgets.dart';

/// API key management (web Account → API keys equivalent).
/// The plaintext token is shown exactly once after creation.
class SettingsApiKeysPage extends StatefulWidget {
  const SettingsApiKeysPage(
      {super.key,
      required this.api,
      required this.token,
      this.onSessionExpired,
      this.loader});

  final NextermApi api;
  final String token;
  final VoidCallback? onSessionExpired;

  /// Test seam (defaults to live `GET /api/accounts/api-keys/`).
  final Future<List<Map<String, dynamic>>> Function()? loader;

  @override
  State<SettingsApiKeysPage> createState() =>
      _SettingsApiKeysPageState();
}

class _SettingsApiKeysPageState extends State<SettingsApiKeysPage> {
  List<Map<String, dynamic>>? _keys;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final keys =
          await (widget.loader?.call() ??
              widget.api.fetchApiKeys(widget.token));
      if (!mounted) return;
      setState(() {
        _keys = keys;
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
        _error = 'Could not load API keys.';
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final name = TextEditingController();
    try {
      final keyName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('New API key'),
          content: TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, name.text.trim()),
              child: const Text('Create'),
            ),
          ],
        ),
      );
      if ((keyName == null || keyName.isEmpty) || !mounted) {
        return;
      }
      late final Map<String, dynamic> created;
      try {
        created = await widget.api
            .createApiKey(widget.token, {'name': keyName});
      } on SessionExpiredException {
        widget.onSessionExpired?.call();
        return;
      } on NextermApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
        return;
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Creation failed.')),
        );
        return;
      }
      if (!mounted) return;
      final token = created['token'] ?? created['key'];
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Copy your key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'This is shown exactly once. Store it somewhere safe.'),
              const SizedBox(height: 12),
              SelectableText('${token ?? '—'}',
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: '${token ?? ''}'));
                Navigator.pop(ctx);
              },
              child: const Text('Copy & close'),
            ),
          ],
        ),
      );
      await _load();
    } finally {
      name.dispose();
    }
  }

  Future<void> _delete(Map<String, dynamic> key) async {
    final rawId = key['id'];
    final id =
        rawId is num ? rawId.toInt() : int.tryParse('$rawId');
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete API key?'),
        content: Text(
            '"${key['name'] ?? 'Key'}" stops working immediately. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.deleteApiKey(widget.token, id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API key deleted.')),
      );
      await _load();
    } on SessionExpiredException {
      widget.onSessionExpired?.call();
    } on NextermApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delete failed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API keys')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-api-key',
        tooltip: 'New API key',
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _keys == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [SettingsStateView.loading()],
              )
            : _error != null && _keys == null
                ? ListView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    children: [
                      SettingsStateView.error(
                          message: _error!, onRetry: _load),
                    ],
                  )
                : (_keys ?? const []).isEmpty
                    ? ListView(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SettingsStateView.empty(
                              message:
                                  'No API keys yet. Create one for scripts and integrations.'),
                        ],
                      )
                    : ListView.builder(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                            16, 8, 16, 96),
                        itemCount: _keys!.length,
                        itemBuilder: (context, i) {
                          final key = _keys![i];
                          return Card(
                            elevation: 0,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHigh,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(16)),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(16)),
                              contentPadding:
                                  const EdgeInsets.only(
                                      left: 16, right: 4),
                              leading: const Icon(
                                  Icons.key_outlined),
                              title: Text(
                                  '${key['name'] ?? 'Key'}',
                                  style: const TextStyle(
                                      fontWeight:
                                          FontWeight.w600)),
                              subtitle: Text(
                                '${key['createdAt'] ?? key['created'] ?? ''}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                    Icons.delete_outline),
                                tooltip: 'Delete API key',
                                onPressed: () => _delete(key),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
