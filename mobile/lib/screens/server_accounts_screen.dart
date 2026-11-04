import 'package:flutter/material.dart';
import '../widgets/app_ui.dart';
import '../utils/app_icons.dart';
import '../models/server_account.dart';
import '../utils/auth_manager.dart';
import '../widgets/floating_navigation_bar.dart';
import '../widgets/nav_scope.dart';
import '../screens/device_setup_screen.dart';

class ServerAccountsScreen extends StatelessWidget {
  final AuthManager authManager;
  const ServerAccountsScreen({super.key, required this.authManager});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppSubPageHeader(
              title: 'Server Connections',
              trailing: AppHeaderAction(
                icon: AppIcons.plus,
                tooltip: 'Add server connection',
                onPressed: () => pushPage(
                  context,
                  (_) => DeviceSetupScreen(
                    authManager: authManager,
                    isAddingServer: true,
                  ),
                  showNavBar: false,
                ),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: authManager.accountManager,
                builder: (context, _) {
                  final accounts = authManager.accountManager.accounts;
                  final activeId = authManager.accountManager.activeAccountId;
                  if (accounts.isEmpty) {
                    return const AppEmptyState(
                      icon: AppIcons.serverNetworkOff,
                      title: 'No server connections',
                      message: 'Add a server to get started',
                    );
                  }
                  return ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      4,
                      12,
                      16 + FloatingNavigationBarInset.of(context),
                    ),
                    itemCount: accounts.length,
                    itemBuilder: (_, i) => _accountTile(
                      context,
                      accounts[i],
                      accounts[i].id == activeId,
                      cs,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountTile(
    BuildContext context,
    ServerAccount a,
    bool active,
    ColorScheme cs,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: AppCard(
      onTap: active ? null : () => authManager.switchAccount(a.id),
      selected: false,
      child: Row(
        children: [
          AppIconBox(
            icon: AppIcons.serverNetwork,
            size: 42,
            background: active
                ? cs.primaryContainer
                : cs.surfaceContainerHighest,
            foreground: active ? cs.onPrimaryContainer : cs.outline,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        a.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Active',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    a.fullName ?? a.username ?? a.displayUrl,
                    style: TextStyle(fontSize: 12, color: cs.outline),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(AppIcons.dotsVertical, color: cs.outline, size: 20),
            tooltip: 'More',
            onSelected: (v) => _onMenu(context, v, a),
            itemBuilder: (_) => [
              if (!active)
                const PopupMenuItem(value: 'switch', child: Text('Switch to')),
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
        ],
      ),
    ),
  );

  void _onMenu(BuildContext context, String action, ServerAccount account) {
    switch (action) {
      case 'switch':
        authManager.switchAccount(account.id);
      case 'rename':
        _showRenameDialog(context, account);
      case 'remove':
        _showRemoveDialog(context, account);
    }
  }

  void _showRenameDialog(BuildContext context, ServerAccount account) {
    final controller = TextEditingController(text: account.label);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Server'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Label',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final l = controller.text.trim();
              if (l.isNotEmpty) {
                account.label = l;
                authManager.accountManager.updateAccount(account);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showRemoveDialog(BuildContext context, ServerAccount account) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Server'),
        content: Text('Remove "${account.label}"? This will log you out.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              authManager.removeAccount(account.id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
