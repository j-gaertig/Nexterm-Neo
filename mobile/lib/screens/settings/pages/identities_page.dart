import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../models/managed_identity.dart';
import '../../../services/account_service.dart';
import '../../../services/server_editor_service.dart';
import '../../../utils/api_exception.dart';
import '../../../utils/app_icons.dart';
import '../../../utils/auth_manager.dart';
import '../../../utils/server_field_config.dart';
import '../../../widgets/app_ui.dart';
import '../ui.dart';

/// Manages the identities (logins and SSH keys) used to connect to servers.
class IdentitiesPage extends StatefulWidget {
  final AuthManager authManager;

  const IdentitiesPage({super.key, required this.authManager});

  @override
  State<IdentitiesPage> createState() => _IdentitiesPageState();
}

class _IdentitiesPageState extends State<IdentitiesPage> {
  List<ManagedIdentity>? _identities;
  bool _loading = true;
  String? _error;
  String _query = '';

  String? get _token => widget.authManager.sessionToken;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null) return;
    try {
      final list = await ServerEditorService.getIdentities(token);
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _identities = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(e, fallback: 'Could not load identities.');
        _loading = false;
      });
    }
  }

  Future<void> _edit([ManagedIdentity? identity]) async {
    final token = _token;
    if (token == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _IdentitySheet(token: token, identity: identity),
    );
    if (saved == true) {
      if (mounted) settingsToast(context, 'Identity saved.');
      await _load();
    }
  }

  Future<void> _delete(ManagedIdentity identity) async {
    final token = _token;
    if (token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete identity?'),
        content: Text(
          '"${identity.name}" will be removed from every server that uses it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AccountService.deleteIdentity(token, identity.id);
      if (!mounted) return;
      settingsToast(context, 'Identity deleted.');
      await _load();
    } catch (e) {
      if (mounted) {
        settingsToast(
          context,
          friendlyApiError(e, fallback: 'Could not delete the identity.'),
        );
      }
    }
  }

  static String _typeLabel(String type) {
    for (final t in ServerEditorConstants.authTypeLabels) {
      if (t['value'] == type) return t['label'] ?? type;
    }
    return type;
  }

  static IconData _typeIcon(String type) => switch (type) {
    'ssh' => AppIcons.key,
    'both' => AppIcons.key,
    _ => AppIcons.lockOutline,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final all = _identities;
    final q = _query.trim().toLowerCase();
    final visible = all == null
        ? const <ManagedIdentity>[]
        : [
            for (final i in all)
              if (q.isEmpty ||
                  i.name.toLowerCase().contains(q) ||
                  i.username.toLowerCase().contains(q))
                i,
          ];

    return SettingsPage(
      title: 'Identities',
      subtitle: 'Logins and keys for your servers',
      onRefresh: _load,
      headerAction: AppHeaderAction(
        icon: AppIcons.plus,
        tooltip: 'New identity',
        onPressed: _edit,
      ),
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (all == null)
          SizedBox(
            height: 360,
            child: AppErrorState(
              message: _error ?? 'Could not load identities.',
              onRetry: _load,
            ),
          )
        else if (all.isEmpty)
          const SizedBox(
            height: 360,
            child: AppEmptyState(
              icon: AppIcons.key,
              title: 'No identities yet',
              message: 'Create an identity to sign in to your servers.',
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: settingsInputDecoration(
                context,
                hint: 'Search identities…',
              ).copyWith(prefixIcon: const Icon(AppIcons.magnify, size: 20)),
            ),
          ),
          if (visible.isEmpty)
            const SizedBox(
              height: 200,
              child: AppEmptyState(
                icon: AppIcons.magnify,
                title: 'No identities match your search',
              ),
            ),
          for (final identity in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                onTap: () => _edit(identity),
                child: Row(
                  children: [
                    AppIconBox(icon: _typeIcon(identity.authType), size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            identity.name.isEmpty ? 'Unnamed' : identity.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (identity.username.isNotEmpty)
                            Text(
                              identity.username,
                              style: TextStyle(fontSize: 12, color: cs.outline),
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: [
                              SettingsPill(_typeLabel(identity.authType)),
                              if (identity.isOrg)
                                SettingsPill(
                                  'Organization',
                                  color: cs.tertiary,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete identity',
                      onPressed: () => _delete(identity),
                      icon: const Icon(AppIcons.deleteOutline, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: cs.errorContainer,
                        foregroundColor: cs.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _IdentitySheet extends StatefulWidget {
  final String token;
  final ManagedIdentity? identity;

  const _IdentitySheet({required this.token, this.identity});

  @override
  State<_IdentitySheet> createState() => _IdentitySheetState();
}

class _IdentitySheetState extends State<_IdentitySheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.identity?.name ?? '',
  );
  late final TextEditingController _username = TextEditingController(
    text: widget.identity?.username ?? '',
  );
  final _password = TextEditingController();
  final _sshKey = TextEditingController();
  final _passphrase = TextEditingController();
  late String _type = widget.identity?.authType ?? 'password';
  bool _showSecrets = false;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.identity != null;
  bool get _usesPassword =>
      _type == 'password' || _type == 'password-only' || _type == 'both';
  bool get _usesKey => _type == 'ssh' || _type == 'both';

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    _sshKey.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _pickKeyFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      final path = result?.files.single.path;
      if (path == null) return;
      final text = await File(path).readAsString();
      if (mounted) setState(() => _sshKey.text = text);
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = friendlyApiError(e, fallback: 'Could not read the key.'),
        );
      }
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the identity a name.');
      return;
    }
    if (_type != 'password-only' && _username.text.trim().isEmpty) {
      setState(() => _error = 'Enter a username.');
      return;
    }
    if (!_isEdit) {
      if (_usesPassword && _password.text.isEmpty) {
        setState(() => _error = 'Enter a password.');
        return;
      }
      if (_usesKey && _sshKey.text.trim().isEmpty) {
        setState(() => _error = 'Add a private key.');
        return;
      }
    }
    final draft = IdentityDraft(
      name: name,
      username: _username.text.trim(),
      authType: _type,
      password: _password.text,
      sshKey: _sshKey.text.trim().isEmpty ? null : _sshKey.text,
      passphrase: _passphrase.text,
      organizationId: widget.identity?.organizationId,
      passwordTouched: _password.text.isNotEmpty,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await ServerEditorService.updateIdentity(
          token: widget.token,
          identityId: widget.identity!.id,
          payload: draft.toPayload(),
        );
      } else {
        await ServerEditorService.createIdentity(
          token: widget.token,
          payload: draft.toPayload(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(e, fallback: 'Could not save the identity.');
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final secretSuffix = IconButton(
      tooltip: _showSecrets ? 'Hide' : 'Show',
      icon: Icon(
        _showSecrets ? AppIcons.eyeOffOutline : AppIcons.eyeOutline,
        size: 20,
      ),
      onPressed: () => setState(() => _showSecrets = !_showSecrets),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppSheetHandle(),
              AppSheetTitle(
                title: _isEdit ? 'Edit identity' : 'New identity',
                icon: AppIcons.key,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: settingsInputDecoration(
                        context,
                        label: 'Name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      isExpanded: true,
                      decoration: settingsInputDecoration(
                        context,
                        label: 'Authentication',
                      ),
                      items: [
                        for (final t in ServerEditorConstants.authTypeLabels)
                          DropdownMenuItem(
                            value: t['value'],
                            child: Text(t['label'] ?? ''),
                          ),
                      ],
                      onChanged: (v) => setState(() => _type = v ?? _type),
                    ),
                    if (_type != 'password-only') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _username,
                        autocorrect: false,
                        decoration: settingsInputDecoration(
                          context,
                          label: 'Username',
                        ),
                      ),
                    ],
                    if (_usesPassword) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: !_showSecrets,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: settingsInputDecoration(
                          context,
                          label: 'Password',
                          hint: _isEdit ? 'Leave empty to keep' : null,
                          suffix: secretSuffix,
                        ),
                      ),
                    ],
                    if (_usesKey) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _sshKey,
                        minLines: 3,
                        maxLines: 6,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        decoration: settingsInputDecoration(
                          context,
                          label: 'Private key',
                          hint: _isEdit
                              ? 'Leave empty to keep the current key'
                              : '-----BEGIN OPENSSH PRIVATE KEY-----',
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _pickKeyFile,
                          icon: const Icon(
                            AppIcons.fileUploadOutline,
                            size: 18,
                          ),
                          label: const Text('Import key file'),
                        ),
                      ),
                      TextField(
                        controller: _passphrase,
                        obscureText: !_showSecrets,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: settingsInputDecoration(
                          context,
                          label: 'Key passphrase (optional)',
                          suffix: secretSuffix,
                        ),
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(color: cs.error, fontSize: 12.5),
                        ),
                      ),
                    const SizedBox(height: 16),
                    SettingsButton(
                      label: _isEdit ? 'Save changes' : 'Create identity',
                      busy: _busy,
                      onPressed: _save,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
