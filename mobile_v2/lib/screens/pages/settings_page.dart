import 'package:flutter/material.dart';

import '../../account/account_models.dart';
import '../../api/nexterm_api.dart';
import '../../auth/session_store.dart';

/// Settings: profile, login sessions, app info + logout.
class SettingsPage extends StatefulWidget {
  const SettingsPage(
      {super.key,
      required this.session,
      required this.api,
      required this.token,
      required this.onLogout,
      this.loadProfile,
      this.loadSessions});

  final SessionInfo session;
  final NextermApi api;
  final String token;
  final VoidCallback onLogout;

  /// Test seams (default to live account/session endpoints).
  final Future<UserInfo> Function()? loadProfile;
  final Future<List<LoginSession>> Function()? loadSessions;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  UserInfo? _profile;
  List<LoginSession>? _sessions;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<UserInfo> _defaultProfile() async =>
      UserInfo.fromJson(await widget.api.fetchMe(widget.token));

  Future<List<LoginSession>> _defaultSessions() async {
    final raw = await widget.api.fetchLoginSessions(widget.token);
    final out = <LoginSession>[];
    for (final m in raw) {
      try {
        out.add(LoginSession.fromJson(m));
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
      final profile =
          await (widget.loadProfile?.call() ?? _defaultProfile());
      final sessions =
          await (widget.loadSessions?.call() ?? _defaultSessions());
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _sessions = sessions;
        _loading = false;
      });
    } on NextermApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load settings.';
        _loading = false;
      });
    }
  }

  Future<void> _revoke(LoginSession login) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke session?'),
        content: const Text(
            'This logs out that device. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.revokeLoginSession(widget.token, login.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session revoked.')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e is NextermApiException
                  ? e.message
                  : 'Revoke failed.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _profile == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  Text('Settings',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  if (_error != null && _profile == null)
                    Card(
                      elevation: 0,
                      color: cs.errorContainer,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!,
                            style: TextStyle(
                                color: cs.onErrorContainer)),
                      ),
                    )
                  else if (_profile != null)
                    _ProfileCard(
                      profile: _profile!,
                      api: widget.api,
                      token: widget.token,
                      serverLabel: widget.session.label,
                    ),
                  const SizedBox(height: 16),
                  Text('Login sessions',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if ((_sessions ?? const []).isEmpty)
                    Text('No other sessions.',
                        style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant))
                  else
                    for (final login in _sessions!)
                      Card(
                        elevation: 0,
                        color: cs.surfaceContainerHigh,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(16)),
                        child: ListTile(
                          leading: const Icon(Icons.smartphone),
                          title: Text(login.userAgent ?? 'Session',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            [
                              if (login.ip != null) login.ip!,
                              if (login.lastActivity != null)
                                _shortDate(login.lastActivity!),
                            ].join(' • '),
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant),
                          ),
                          trailing: TextButton(
                            onPressed: () => _revoke(login),
                            child: const Text('Revoke'),
                          ),
                        ),
                      ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    color: cs.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.logout,
                            color: cs.onErrorContainer, size: 20),
                      ),
                      title: const Text('Log out',
                          style:
                              TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text(
                          'Delete the session on this device',
                          style: TextStyle(fontSize: 12)),
                      onTap: () => _confirmLogout(context),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Nexterm V2 · ${widget.session.label}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.outline),
                      textAlign: TextAlign.center),
                ],
              ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
            'This deletes the session on this device. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onLogout();
  }
}

String _shortDate(DateTime dt) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.day)}.${two(dt.month)}. ${two(dt.hour)}:${two(dt.minute)}';
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard(
      {required this.profile,
      required this.api,
      required this.token,
      required this.serverLabel});

  final UserInfo profile;
  final NextermApi api;
  final String token;
  final String serverLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHigh,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ClipOval(
              child: Image.network(
                profile.avatarUrl(api.baseUrl, token),
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 52,
                  height: 52,
                  color: cs.primaryContainer,
                  child: Icon(Icons.person,
                      color: cs.onPrimaryContainer),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(profile.displayName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16)),
                      ),
                      if (profile.isAdmin)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Admin',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onPrimaryContainer)),
                        ),
                    ],
                  ),
                  Text(serverLabel,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
