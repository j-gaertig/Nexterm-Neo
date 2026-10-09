import 'package:flutter/material.dart';

import '../../api/nexterm_api.dart';
import '../../servers/identity.dart';
import '../../servers/org_models.dart';
import '../../settings/settings_widgets.dart';

/// Server identities (`GET /api/identities/list` + PUT/PATCH/DELETE).
///
/// Web equivalent: Settings → Identities. Secrets are write-only —
/// the list never returns passwords/keys.
class SettingsIdentitiesPage extends StatefulWidget {
  const SettingsIdentitiesPage(
      {super.key,
      required this.api,
      required this.token,
      this.onSessionExpired,
      this.loader});

  final NextermApi api;
  final String token;
  final VoidCallback? onSessionExpired;

  /// Test seam (defaults to live `GET /api/identities/list`).
  final Future<List<Identity>> Function()? loader;

  @override
  State<SettingsIdentitiesPage> createState() =>
      _SettingsIdentitiesPageState();
}

class _SettingsIdentitiesPageState extends State<SettingsIdentitiesPage> {
  List<Identity>? _identities;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<Identity>> _defaultLoad() async {
    final raw = await widget.api.fetchIdentities(widget.token);
    final out = <Identity>[];
    for (final m in raw) {
      try {
        out.add(Identity.fromJson(m));
      } catch (_) {}
    }
    return out;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items =
          await (widget.loader?.call() ?? _defaultLoad());
      if (!mounted) return;
      setState(() {
        _identities = items;
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
        _error = 'Could not load identities.';
        _loading = false;
      });
    }
  }

  Future<void> _confirmDelete(Identity identity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete identity?'),
        content: Text(
            '"${identity.name}" will stop working for new sessions. Continue?'),
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
      await widget.api.deleteIdentity(widget.token, identity.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identity deleted.')),
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

  Future<void> _openEditor({Identity? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _IdentityDialog(
        api: widget.api,
        token: widget.token,
        existing: existing,
        onSessionExpired: widget.onSessionExpired,
      ),
    );
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Identities')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-identity',
        tooltip: 'New identity',
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _identities == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SettingsStateView.loading(),
                ],
              )
            : _error != null && _identities == null
                ? ListView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    children: [
                      SettingsStateView.error(
                          message: _error!, onRetry: _load),
                    ],
                  )
                : (_identities ?? const []).isEmpty
                    ? ListView(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SettingsStateView.empty(
                              message:
                                  'No identities yet. Add one to reuse logins across servers.'),
                        ],
                      )
                    : ListView.builder(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        padding:
                            const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: _identities!.length,
                        itemBuilder: (context, i) {
                          final identity = _identities![i];
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
                              leading: Icon(
                                  _iconForType(identity.type)),
                              title: Text(identity.name,
                                  style: const TextStyle(
                                      fontWeight:
                                          FontWeight.w600)),
                              subtitle: Text(
                                [
                                  identity.username ?? 'no username',
                                  identity.type,
                                ].join(' • '),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                              ),
                              trailing: PopupMenuButton<String>(
                                tooltip: 'Identity actions',
                                icon:
                                    const Icon(Icons.more_vert),
                                onSelected: (v) {
                                  if (v == 'edit') {
                                    _openEditor(
                                        existing: identity);
                                  } else if (v == 'delete') {
                                    _confirmDelete(identity);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit')),
                                  PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete')),
                                ],
                              ),
                              onTap: () => _openEditor(
                                  existing: identity),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

IconData _iconForType(String type) {
  switch (type) {
    case 'ssh':
    case 'both':
      return Icons.key;
    case 'password-only':
    case 'password':
      return Icons.password;
    default:
      return Icons.badge_outlined;
  }
}

/// Create/edit dialog. Password/key fields are write-only and only
/// sent when non-empty (edit keeps existing secrets otherwise).
class _IdentityDialog extends StatefulWidget {
  const _IdentityDialog(
      {required this.api,
      required this.token,
      this.existing,
      this.onSessionExpired});

  final NextermApi api;
  final String token;
  final Identity? existing;
  final VoidCallback? onSessionExpired;

  @override
  State<_IdentityDialog> createState() => _IdentityDialogState();
}

class _IdentityDialogState extends State<_IdentityDialog> {
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _sshKey;
  late final TextEditingController _passphrase;
  String _type = 'password';
  bool _saving = false;
  String? _error;
  List<OrgRef> _orgs = [];
  int? _organizationId;

  /// Set when editing an identity whose server-side type is unknown to
  /// this app version — saving is blocked so we never overwrite the
  /// type with a coerced default.
  bool _unsupportedType = false;

  static const _types = ['password', 'ssh', 'both', 'password-only'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _username = TextEditingController(text: e?.username ?? '');
    _password = TextEditingController();
    _sshKey = TextEditingController();
    _passphrase = TextEditingController();
    if (e != null) {
      if (_types.contains(e.type)) {
        _type = e.type;
      } else {
        _unsupportedType = true;
      }
    }
    loadOrgRefs(
      () => widget.api.fetchOrganizations(widget.token),
    ).then((orgs) {
      if (mounted) setState(() => _orgs = orgs);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    _sshKey.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  bool get _needsPassword =>
      _type == 'password' ||
      _type == 'both' ||
      _type == 'password-only';
  bool get _needsSsh => _type == 'ssh' || _type == 'both';

  Future<void> _save() async {
    if (_unsupportedType) {
      setState(() => _error =
          'Unsupported identity type — editing is disabled.');
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = <String, dynamic>{
        'name': name,
        'type': _type,
        if (_username.text.trim().isNotEmpty)
          'username': _username.text.trim(),
        if (_password.text.isNotEmpty) 'password': _password.text,
        if (_sshKey.text.isNotEmpty) 'sshKey': _sshKey.text,
        if (_passphrase.text.isNotEmpty)
          'passphrase': _passphrase.text,
      };
      // Organization scope is set at creation (moving uses the
      // dedicated move endpoint, not the edit dialog).
      final existing = widget.existing;
      final orgId = _organizationId;
      if (existing == null && orgId != null) {
        payload['organizationId'] = orgId;
      }
      if (existing == null) {
        await widget.api.createIdentity(widget.token, payload);
      } else {
        await widget.api
            .updateIdentity(widget.token, existing.id, payload);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on SessionExpiredException {
      widget.onSessionExpired?.call();
    } on NextermApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Save failed.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          widget.existing == null ? 'New identity' : 'Edit identity'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_unsupportedType) ...[
              Text(
                'Type "${widget.existing?.type}" is not supported by this app version. Editing is disabled.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              decoration: const InputDecoration(
                  labelText: 'Username (optional)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                  labelText: 'Type', border: OutlineInputBorder()),
              items: [
                for (final t in _types)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _type = v);
              },
            ),
            if (widget.existing == null && _orgs.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _organizationId,
                decoration: const InputDecoration(
                    labelText: 'Organization',
                    border: OutlineInputBorder()),
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
                onChanged: (v) =>
                    setState(() => _organizationId = v),
              ),
            ],
            if (_needsPassword) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: widget.existing == null
                      ? 'Password'
                      : 'New password (leave empty to keep)',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            if (_needsSsh) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _sshKey,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: widget.existing == null
                      ? 'Private SSH key'
                      : 'New SSH key (leave empty to keep)',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.multiline,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passphrase,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Key passphrase (optional)',
                    border: OutlineInputBorder()),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_saving || _unsupportedType) ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
