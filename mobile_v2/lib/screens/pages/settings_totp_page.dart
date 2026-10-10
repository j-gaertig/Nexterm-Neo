import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/nexterm_api.dart';

/// TOTP two-factor management (web Account → 2FA equivalent):
/// shows the secret + setup URL, verifies a code to enable,
/// disables on demand. State comes from `UserInfo.totpEnabled`.
class SettingsTotpPage extends StatefulWidget {
  const SettingsTotpPage(
      {super.key,
      required this.api,
      required this.token,
      required this.enabled,
      this.onSessionExpired,
      this.onChanged});

  final NextermApi api;
  final String token;

  /// Current server-side state (`GET /api/accounts/me`).
  final bool enabled;
  final VoidCallback? onSessionExpired;

  /// Called after enable/disable so the hub reloads the profile.
  final VoidCallback? onChanged;

  @override
  State<SettingsTotpPage> createState() => _SettingsTotpPageState();
}

class _SettingsTotpPageState extends State<SettingsTotpPage> {
  final _code = TextEditingController();
  late bool _enabled;
  String? _secret;
  String? _url;
  String? _error;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.enabled;
    if (!_enabled) _fetchSecret();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _fetchSecret() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final data =
          await widget.api.fetchTotpSecret(widget.token);
      if (!mounted) return;
      setState(() {
        _secret = data['secret'] as String?;
        _url = data['url'] as String?;
        _working = false;
      });
    } on SessionExpiredException {
      if (mounted) setState(() => _working = false);
      widget.onSessionExpired?.call();
    } on NextermApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _working = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load setup data.';
        _working = false;
      });
    }
  }

  Future<void> _enable() async {
    final code = int.tryParse(_code.text.trim());
    if (code == null) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.api.enableTotp(widget.token, code);
      if (!mounted) return;
      setState(() {
        _enabled = true;
        _working = false;
      });
      widget.onChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Two-factor enabled.')),
      );
    } on SessionExpiredException {
      if (mounted) setState(() => _working = false);
      widget.onSessionExpired?.call();
    } on NextermApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _working = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Enable failed.';
        _working = false;
      });
    }
  }

  Future<void> _disable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disable two-factor?'),
        content: const Text(
            'Your account loses the extra protection. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.api.disableTotp(widget.token);
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _working = false;
        _secret = null;
        _url = null;
      });
      widget.onChanged?.call();
      await _fetchSecret();
    } on SessionExpiredException {
      if (mounted) setState(() => _working = false);
      widget.onSessionExpired?.call();
    } on NextermApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _working = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Disable failed.';
        _working = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Two-factor')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              color: cs.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: Icon(
                    _enabled
                        ? Icons.verified_user
                        : Icons.verified_user_outlined,
                    color: cs.primary),
                title: Text(
                    _enabled ? 'Enabled' : 'Disabled',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600)),
                subtitle: Text(
                    _enabled
                        ? 'Login needs an authenticator code'
                        : 'Add an authenticator for extra protection',
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
            if (_enabled) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _working ? null : _disable,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16)),
                child: const Text('Disable two-factor'),
              ),
            ] else ...[
              const SizedBox(height: 16),
              Text(
                'Add this account to your authenticator app, then verify a code.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (_working && _secret == null)
                const Center(child: CircularProgressIndicator())
              else if (_secret != null) ...[
                Text('Secret',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(
                            fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                SelectableText(_secret!,
                    style: const TextStyle(
                        fontFamily: 'monospace')),
                if (_url != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(_url!,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant)),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy_outlined,
                        size: 18),
                    label: const Text('Copy secret'),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _secret!));
                      ScaffoldMessenger.of(context)
                          .showSnackBar(
                        const SnackBar(
                            content: Text('Copied.')),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '6-digit code',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _enable(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _working ? null : _enable,
                  style: FilledButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(
                              vertical: 16)),
                  child: _working
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                      : const Text('Verify & enable'),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style:
                      TextStyle(color: cs.error, fontSize: 12)),
              if (!_enabled && _secret == null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _working ? null : _fetchSecret,
                  child: const Text('Retry'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
