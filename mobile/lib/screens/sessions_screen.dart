import 'package:flutter/material.dart';
import '../widgets/app_ui.dart';
import '../utils/app_icons.dart';
import '../models/session_model.dart';
import '../services/auth_service.dart';
import '../utils/auth_manager.dart';
import '../widgets/floating_navigation_bar.dart';

class SessionsScreen extends StatefulWidget {
  final AuthManager authManager;
  const SessionsScreen({super.key, required this.authManager});
  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  List<SessionModel>? _sessions;
  bool _loading = false;
  final _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = widget.authManager.sessionToken;
    if (token != null) {
      final sessions = await _auth.listSessions(token);
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _loading = false;
        });
      }
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _revoke(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out Device'),
        content: const Text('Are you sure you want to sign out this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    final success = await _auth.revokeSession(token, id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Device signed out' : 'Failed to sign out device',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (success) _load();
  }

  IconData _icon(String? ua) {
    if (ua == null) return AppIcons.devices;
    if (ua.startsWith('NextermConnector/')) return AppIcons.application;
    if (ua.startsWith('NextermMobile/')) return AppIcons.cellphoneLink;
    final l = ua.toLowerCase();
    if (l.contains('mobile') || l.contains('android') || l.contains('iphone')) {
      return AppIcons.cellphone;
    }
    if (l.contains('tablet') || l.contains('ipad')) return AppIcons.tablet;
    if (l.contains('mac') || l.contains('windows') || l.contains('linux')) {
      return AppIcons.laptop;
    }
    return AppIcons.devices;
  }

  String _ago(DateTime? d) {
    if (d == null) return 'Unknown';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  String _device(String? ua) {
    if (ua == null) return 'Unknown Device';
    final conn = RegExp(
      r'^NextermConnector/([\d.]+)\s*\(([^;]+);',
    ).firstMatch(ua);
    if (conn != null) {
      return 'Connector ${conn.group(1)} · ${conn.group(2)?.trim()}';
    }
    final mobile = RegExp(
      r'^NextermMobile/([\d.]+)\s*\(([^;)]+)',
    ).firstMatch(ua);
    if (mobile != null) {
      final p = mobile.group(2)?.trim() ?? '';
      return 'Mobile ${mobile.group(1)} · ${p.isNotEmpty ? p[0].toUpperCase() + p.substring(1) : p}';
    }
    for (final b in ['Chrome', 'Firefox', 'Safari', 'Edge']) {
      if (ua.contains(b) && (b != 'Safari' || !ua.contains('Chrome'))) {
        for (final os in [
          'Windows',
          'Mac',
          'Linux',
          'Android',
          'iPhone',
          'iPad',
        ]) {
          if (ua.contains(os)) return '$b · $os';
        }
        return b;
      }
    }
    return 'Unknown Device';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppSubPageHeader(
              title: 'Signed-in Devices',
              trailing: IconButton(
                icon: const Icon(AppIcons.refresh, size: 22),
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _sessions == null || _sessions!.isEmpty
                          ? _empty()
                          : _list(cs),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() => LayoutBuilder(
    builder: (context, constraints) => ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: constraints.maxHeight,
          child: const AppEmptyState(
            icon: AppIcons.monitor,
            title: 'No other devices',
            message: 'Only this device is active',
          ),
        ),
      ],
    ),
  );

  Widget _list(ColorScheme cs) => ListView.builder(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: EdgeInsets.fromLTRB(
      12,
      4,
      12,
      16 + FloatingNavigationBarInset.of(context),
    ),
    itemCount: _sessions!.length,
    itemBuilder: (_, i) => _sessionTile(_sessions![i], cs),
  );

  Widget _sessionTile(SessionModel s, ColorScheme cs) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: AppCard(
      child: Row(
        children: [
          AppIconBox(icon: _icon(s.userAgent), size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _device(s.userAgent),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '${s.ip ?? 'Unknown IP'} · ${_ago(s.lastActivity)}',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Sign out device',
            onPressed: () => _revoke(s.id),
            icon: const Icon(AppIcons.deleteOutline, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: cs.errorContainer,
              foregroundColor: cs.onErrorContainer,
            ),
          ),
        ],
      ),
    ),
  );
}
