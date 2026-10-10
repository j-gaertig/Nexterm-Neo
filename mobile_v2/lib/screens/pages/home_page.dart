import 'package:flutter/material.dart';

import '../../api/nexterm_api.dart';
import '../../remote/viewer.dart';
import '../../servers/server_models.dart';
import '../pages/servers_page.dart' show protocolIcon;

/// Home dashboard: greeting + recent servers with tap-to-connect.
class HomePage extends StatefulWidget {
  const HomePage(
      {super.key,
      required this.api,
      required this.token,
      this.onSessionExpired,
      required this.label,
      this.loadRecents});

  final NextermApi api;
  final String token;

  /// Called on HTTP 401 so expired sessions return to login.
  final VoidCallback? onSessionExpired;
  final String label;

  /// Test seam (defaults to `GET /api/entries/recent`).
  final Future<List<ServerEntry>> Function()? loadRecents;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<ServerEntry>? _recents;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<ServerEntry>> _defaultLoad() async {
    final raw = await widget.api.fetchRecent(widget.token);
    final out = <ServerEntry>[];
    for (final m in raw) {
      try {
        // `GET /api/entries/recent` returns `{entryId, name, ...}`
        // (no `id`/`ip`) — map onto the list shape before parsing.
        final mapped = Map<String, dynamic>.from(m);
        mapped['id'] ??= mapped['entryId'];
        if (mapped['type'] == null || mapped['type'] == 'server') {
          out.add(ServerEntry.fromJson(mapped));
        }
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
      final recents =
          await (widget.loadRecents?.call() ?? _defaultLoad());
      if (!mounted) return;
      setState(() {
        _recents = recents;
        _loading = false;
      });
    } on SessionExpiredException {
      if (!mounted) return;
      setState(() => _loading = false);
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
        _error = 'Could not load recent servers.';
        _loading = false;
      });
    }
  }

  Future<void> _quickConnect(ServerEntry entry) {
    return startNewSession(context,
        api: widget.api,
        token: widget.token,
        entry: entry,
        kind: entry.quickConnectKind,
        onSessionExpired: widget.onSessionExpired);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 44,
                    height: 44,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.terminal, size: 36),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome back',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text('Connected to ${widget.label}',
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Recent servers',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                elevation: 0,
                color: cs.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      OutlinedButton(
                          onPressed: _load,
                          child: const Text('Retry')),
                    ],
                  ),
                ),
              )
            else if ((_recents ?? const []).isEmpty)
              Card(
                elevation: 0,
                color: cs.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No recent servers yet. Connect from the Servers tab.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              for (final entry in _recents!)
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
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                          protocolIcon(entry.protocol),
                          color: cs.onPrimaryContainer,
                          size: 20),
                    ),
                    title: Text(entry.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${formatServerSubtitle(entry)} • tap to connect',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant),
                    ),
                    trailing: Icon(Icons.bolt,
                        color: cs.primary),
                    onTap: () => _quickConnect(entry),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
