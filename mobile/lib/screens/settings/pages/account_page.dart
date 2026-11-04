import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/account_service.dart';
import '../../../utils/api_exception.dart';
import '../../../utils/app_icons.dart';
import '../../../utils/auth_manager.dart';
import '../../../widgets/app_ui.dart';
import '../ui.dart';

/// Profile name, password, two-factor authentication and session sync.
class AccountPage extends StatefulWidget {
  final AuthManager authManager;

  const AccountPage({super.key, required this.authManager});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  AccountProfile? _profile;
  bool _loading = true;
  String? _error;

  final _first = TextEditingController();
  final _last = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _savingName = false;
  bool _savingPassword = false;
  bool _showPassword = false;
  bool _twoFactorBusy = false;
  String? _passwordError;

  String? get _token => widget.authManager.sessionToken;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null) return;
    try {
      final profile = await AccountService.getMe(token);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _first.text = profile.firstName;
        _last.text = profile.lastName;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(e, fallback: 'Could not load your profile.');
        _loading = false;
      });
    }
  }

  Future<void> _saveName() async {
    final token = _token;
    if (token == null) return;
    final first = _first.text.trim();
    final last = _last.text.trim();
    if (first.isEmpty || last.isEmpty) {
      settingsToast(context, 'Enter a first and a last name.');
      return;
    }
    setState(() => _savingName = true);
    try {
      await AccountService.updateName(
        token: token,
        firstName: first,
        lastName: last,
      );
      if (!mounted) return;
      settingsToast(context, 'Name updated.');
      await _load();
    } catch (e) {
      if (mounted) {
        settingsToast(
          context,
          friendlyApiError(e, fallback: 'Could not update your name.'),
        );
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _changePassword() async {
    final token = _token;
    if (token == null) return;
    final value = _password.text;
    if (value.length < 3) {
      setState(() => _passwordError = 'Use at least 3 characters.');
      return;
    }
    if (value != _confirm.text) {
      setState(() => _passwordError = 'The passwords do not match.');
      return;
    }
    setState(() {
      _passwordError = null;
      _savingPassword = true;
    });
    try {
      await AccountService.changePassword(token: token, password: value);
      if (!mounted) return;
      _password.clear();
      _confirm.clear();
      settingsToast(context, 'Password changed.');
    } catch (e) {
      if (mounted) {
        setState(
          () => _passwordError = friendlyApiError(
            e,
            fallback: 'Could not change your password.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _enableTwoFactor() async {
    final token = _token;
    if (token == null) return;
    final enabled = await showDialog<bool>(
      context: context,
      builder: (_) => _TotpSetupDialog(token: token),
    );
    if (enabled == true && mounted) {
      settingsToast(context, 'Two-factor authentication enabled.');
      await _load();
    }
  }

  Future<void> _disableTwoFactor() async {
    final token = _token;
    if (token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disable two-factor authentication?'),
        content: const Text(
          'Your account will only be protected by your password.',
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
            child: const Text('Disable'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _twoFactorBusy = true);
    try {
      await AccountService.disableTotp(token);
      if (!mounted) return;
      settingsToast(context, 'Two-factor authentication disabled.');
      await _load();
    } catch (e) {
      if (mounted) {
        settingsToast(
          context,
          friendlyApiError(e, fallback: 'Could not disable 2FA.'),
        );
      }
    } finally {
      if (mounted) setState(() => _twoFactorBusy = false);
    }
  }

  Future<void> _setSessionSync(String mode) async {
    final token = _token;
    final profile = _profile;
    if (token == null || profile == null || profile.sessionSync == mode) return;
    try {
      await AccountService.setSessionSync(token, mode);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) {
        settingsToast(
          context,
          friendlyApiError(e, fallback: 'Could not update the setting.'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final profile = _profile;
    if (_loading) {
      return const SettingsPage(
        title: 'Account',
        children: [
          Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    if (profile == null) {
      return SettingsPage(
        title: 'Account',
        children: [
          SizedBox(
            height: 360,
            child: AppErrorState(
              message: _error ?? 'Could not load your profile.',
              onRetry: () {
                setState(() => _loading = true);
                _load();
              },
            ),
          ),
        ],
      );
    }

    return SettingsPage(
      title: 'Account',
      subtitle: '@${profile.username}',
      onRefresh: _load,
      children: [
        SettingsGroup(
          title: 'Profile',
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  TextField(
                    controller: _first,
                    textCapitalization: TextCapitalization.words,
                    decoration: settingsInputDecoration(
                      context,
                      label: 'First name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _last,
                    textCapitalization: TextCapitalization.words,
                    decoration: settingsInputDecoration(
                      context,
                      label: 'Last name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SettingsButton(
                    label: 'Save name',
                    busy: _savingName,
                    onPressed: _saveName,
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Password',
          footer: 'Changing your password does not sign out other devices.',
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  TextField(
                    controller: _password,
                    obscureText: !_showPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: settingsInputDecoration(
                      context,
                      label: 'New password',
                      suffix: IconButton(
                        tooltip: _showPassword ? 'Hide' : 'Show',
                        icon: Icon(
                          _showPassword
                              ? AppIcons.eyeOffOutline
                              : AppIcons.eyeOutline,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: !_showPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: settingsInputDecoration(
                      context,
                      label: 'Confirm new password',
                    ),
                  ),
                  if (_passwordError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _passwordError!,
                          style: TextStyle(color: cs.error, fontSize: 12.5),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SettingsButton(
                    label: 'Change password',
                    busy: _savingPassword,
                    onPressed: _changePassword,
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Two-factor authentication',
          footer:
              'Adds a one-time code from an authenticator app to your sign-in.',
          children: [
            SettingsTile(
              icon: AppIcons.lockOutline,
              title: 'Authenticator app',
              subtitle: profile.totpEnabled
                  ? 'Active on your account'
                  : 'Not set up',
              chevron: false,
              trailing: SettingsPill(
                profile.totpEnabled ? 'On' : 'Off',
                color: profile.totpEnabled ? const Color(0xFF4CAF50) : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: profile.totpEnabled
                  ? SettingsButton(
                      label: 'Disable two-factor authentication',
                      outlined: true,
                      destructive: true,
                      busy: _twoFactorBusy,
                      onPressed: _disableTwoFactor,
                    )
                  : SettingsButton(
                      label: 'Set up two-factor authentication',
                      busy: _twoFactorBusy,
                      onPressed: _enableTwoFactor,
                    ),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Session synchronization',
          footer:
              'Controls which of your open sessions are shared between devices.',
          children: [
            for (final option in const [
              (
                'across_devices',
                'Across devices',
                'Sessions follow you to every device',
              ),
              (
                'same_browser',
                'Same browser',
                'Only within the same browser or app',
              ),
              ('same_tab', 'Same tab', 'Each tab keeps its own sessions'),
            ])
              SettingsTile(
                icon: AppIcons.devices,
                title: option.$2,
                subtitle: option.$3,
                chevron: false,
                onTap: () => _setSessionSync(option.$1),
                trailing: Icon(
                  profile.sessionSync == option.$1
                      ? AppIcons.checkCircle
                      : AppIcons.checkboxBlankOutline,
                  size: 22,
                  color: profile.sessionSync == option.$1
                      ? cs.primary
                      : cs.outline,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TotpSetupDialog extends StatefulWidget {
  final String token;

  const _TotpSetupDialog({required this.token});

  @override
  State<_TotpSetupDialog> createState() => _TotpSetupDialogState();
}

class _TotpSetupDialogState extends State<_TotpSetupDialog> {
  final _code = TextEditingController();
  String? _secret;
  String? _url;
  String? _error;
  bool _loading = true;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await AccountService.getTotpSecret(widget.token);
      if (!mounted) return;
      setState(() {
        _secret = data.secret;
        _url = data.url;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(e, fallback: 'Could not load the secret.');
        _loading = false;
      });
    }
  }

  Future<void> _verify() async {
    final code = int.tryParse(_code.text.trim());
    if (code == null) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await AccountService.enableTotp(widget.token, code);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(e, fallback: 'The code is not valid.');
        _verifying = false;
      });
    }
  }

  Future<void> _openAuthenticator() async {
    final url = _url;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        setState(() => _error = 'No authenticator app found. Copy the key.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No authenticator app found. Copy the key.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Set up 2FA'),
      content: _loading
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add this key to your authenticator app, then enter the '
                    'code it shows.',
                  ),
                  const SizedBox(height: 12),
                  if (_secret != null && _secret!.isNotEmpty)
                    AppCard(
                      onSheet: true,
                      radius: AppRadii.control,
                      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _secret!,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy key',
                            icon: const Icon(AppIcons.contentCopy, size: 18),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: _secret!),
                              );
                              if (mounted) {
                                setState(() => _error = null);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _openAuthenticator,
                    icon: const Icon(AppIcons.web, size: 18),
                    label: const Text('Open in authenticator app'),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    autofocus: true,
                    onSubmitted: (_) => _verify(),
                    decoration: const InputDecoration(
                      labelText: 'Verification code',
                      counterText: '',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(color: cs.error, fontSize: 12.5),
                      ),
                    ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading || _verifying ? null : _verify,
          child: _verifying
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enable'),
        ),
      ],
    );
  }
}
