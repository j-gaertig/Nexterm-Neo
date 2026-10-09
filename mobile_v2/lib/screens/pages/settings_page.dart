import 'package:flutter/material.dart';

import '../../app_info.dart';
import '../../auth/session_store.dart';

/// Einstellungen: Server-Info + Logout.
class SettingsPage extends StatelessWidget {
  const SettingsPage(
      {super.key, required this.session, required this.onLogout});

  final SessionInfo session;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Einstellungen',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
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
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.dns,
                    color: cs.onPrimaryContainer, size: 20),
              ),
              title: Text(session.label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(session.baseUrl,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          ),
          const SizedBox(height: 8),
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
              title: const Text('Abmelden',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Session auf diesem Gerät löschen',
                  style: TextStyle(fontSize: 12)),
              onTap: () => _confirmLogout(context),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 24),
          Text('Nexterm V2 · ${AppInfo.version}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.outline),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abmelden?'),
        content: const Text(
            'Die Session auf diesem Gerät wird gelöscht. Fortfahren?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );
    if (confirmed == true) onLogout();
  }
}
