import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/account_service.dart';
import '../../../utils/api_exception.dart';
import '../../../utils/app_icons.dart';
import '../../../utils/auth_manager.dart';
import '../../../widgets/app_ui.dart';
import '../ui.dart';

/// Lists, creates and revokes personal API keys.
class ApiKeysPage extends StatefulWidget {
  final AuthManager authManager;

  const ApiKeysPage({super.key, required this.authManager});

  @override
  State<ApiKeysPage> createState() => _ApiKeysPageState();
}

class _ApiKeysPageState extends State<ApiKeysPage> {
  List<ApiKeyInfo>? _keys;
  bool _loading = true;
  String? _error;

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
      final keys = await AccountService.listApiKeys(token);
      if (!mounted) return;
      setState(() {
        _keys = keys;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(e, fallback: 'Could not load API keys.');
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final token = _token;
    if (token == null) return;
    final created = await showDialog<ApiKeyInfo>(
      context: context,
      builder: (_) => _CreateKeyDialog(token: token),
    );
    if (created == null || !mounted) return;
    await _load();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _KeyCreatedDialog(created: created),
    );
  }

  Future<void> _delete(ApiKeyInfo key) async {
    final token = _token;
    if (token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete API key?'),
        content: Text(
          'Anything using "${key.name}" will lose access immediately.',
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
      await AccountService.deleteApiKey(token, key.id);
      if (!mounted) return;
      settingsToast(context, 'API key deleted.');
      await _load();
    } catch (e) {
      if (mounted) {
        settingsToast(
          context,
          friendlyApiError(e, fallback: 'Could not delete the API key.'),
        );
      }
    }
  }

  static String _date(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}.${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final keys = _keys;
    return SettingsPage(
      title: 'API keys',
      subtitle: 'Access Nexterm from scripts and tools',
      onRefresh: _load,
      headerAction: AppHeaderAction(
        icon: AppIcons.plus,
        tooltip: 'Create API key',
        onPressed: _create,
      ),
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (keys == null)
          SizedBox(
            height: 360,
            child: AppErrorState(
              message: _error ?? 'Could not load API keys.',
              onRetry: _load,
            ),
          )
        else if (keys.isEmpty)
          const SizedBox(
            height: 360,
            child: AppEmptyState(
              icon: AppIcons.key,
              title: 'No API keys yet',
              message: 'Create a key to use the Nexterm API.',
            ),
          )
        else
          for (final key in keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: Row(
                  children: [
                    const AppIconBox(icon: AppIcons.key, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            key.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            key.prefix,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.outline,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              key.lastUsedAt == null
                                  ? 'Never used'
                                  : 'Used ${_date(key.lastUsedAt)}',
                              if (key.expiresAt != null)
                                'Expires ${_date(key.expiresAt)}',
                            ].join(' · '),
                            style: TextStyle(fontSize: 11.5, color: cs.outline),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete key',
                      onPressed: () => _delete(key),
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
    );
  }
}

class _CreateKeyDialog extends StatefulWidget {
  final String token;

  const _CreateKeyDialog({required this.token});

  @override
  State<_CreateKeyDialog> createState() => _CreateKeyDialogState();
}

class _CreateKeyDialogState extends State<_CreateKeyDialog> {
  final _name = TextEditingController();
  // null = never expires
  int? _days = 90;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the key a name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await AccountService.createApiKey(
        token: widget.token,
        name: name,
        expiresAt: _days == null
            ? null
            : DateTime.now().add(Duration(days: _days!)),
      );
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(e, fallback: 'Could not create the key.');
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('New API key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
          const Text('Expires', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final option in const [
                (30, '30 days'),
                (90, '90 days'),
                (365, '1 year'),
                (null, 'Never'),
              ])
                ChoiceChip(
                  label: Text(option.$2),
                  selected: _days == option.$1,
                  side: appBorderSide(cs),
                  onSelected: (_) => setState(() => _days = option.$1),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: cs.error, fontSize: 12.5),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

class _KeyCreatedDialog extends StatelessWidget {
  final ApiKeyInfo created;

  const _KeyCreatedDialog({required this.created});

  @override
  Widget build(BuildContext context) {
    final token = created.token ?? '';
    return AlertDialog(
      title: const Text('Copy your key now'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This is the only time the full key is shown. Store it somewhere '
            'safe.',
          ),
          const SizedBox(height: 12),
          AppCard(
            onSheet: true,
            radius: AppRadii.control,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              token,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: token.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: token));
                  if (context.mounted) settingsToast(context, 'Key copied.');
                },
          icon: const Icon(AppIcons.contentCopy, size: 18),
          label: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
