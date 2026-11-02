import 'package:flutter/material.dart';

import '../../models/server_account.dart';
import '../../utils/app_icons.dart';
import '../../utils/auth_manager.dart';

/// Compact instance picker for the Servers header.
///
/// Shows the label of the signed-in Nexterm instance and lets the user switch
/// between every stored server connection. The actual data reload is driven by
/// [AuthManager] listeners in the screens.
class InstanceSwitcher extends StatelessWidget {
  static const String _manageValue = '__manage_instances__';

  final AuthManager authManager;
  final VoidCallback? onManageInstances;

  const InstanceSwitcher({
    super.key,
    required this.authManager,
    this.onManageInstances,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: authManager,
      builder: (context, _) {
        final accounts = authManager.accountManager.accounts;
        final active = authManager.accountManager.activeAccount;
        if (accounts.isEmpty || active == null) return const SizedBox.shrink();

        final label = _labelOf(active);
        return PopupMenuButton<String>(
          key: const ValueKey('instance-switcher'),
          tooltip: 'Switch server instance',
          position: PopupMenuPosition.under,
          offset: const Offset(0, 6),
          color: cs.surfaceContainerHigh,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant),
          ),
          constraints: const BoxConstraints(minWidth: 260, maxWidth: 340),
          onSelected: (value) {
            if (value == _manageValue) {
              onManageInstances?.call();
              return;
            }
            if (value == active.id) return;
            authManager.switchAccount(value);
          },
          itemBuilder: (context) => [
            for (final account in accounts)
              PopupMenuItem<String>(
                value: account.id,
                height: 64,
                child: _InstanceMenuItem(
                  account: account,
                  active: account.id == active.id,
                ),
              ),
            if (onManageInstances != null) ...[
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: _manageValue,
                height: 48,
                child: Row(
                  children: [
                    Icon(AppIcons.serverNetwork, size: 18, color: cs.primary),
                    const SizedBox(width: 10),
                    Text(
                      'Manage instances',
                      style: TextStyle(fontSize: 14, color: cs.primary),
                    ),
                  ],
                ),
              ),
            ],
          ],
          child: Semantics(
            button: true,
            label: 'Switch server instance, current: $label',
            excludeSemantics: true,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 168),
              padding: const EdgeInsets.fromLTRB(9, 6, 7, 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.65),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      AppIcons.dns,
                      size: 14,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(AppIcons.chevronDown, size: 16, color: cs.outline),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _labelOf(ServerAccount account) {
    final label = account.label.trim();
    return label.isEmpty ? account.displayUrl : label;
  }
}

class _InstanceMenuItem extends StatelessWidget {
  final ServerAccount account;
  final bool active;

  const _InstanceMenuItem({required this.account, required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = account.fullName ?? account.username ?? account.displayUrl;

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: active ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            AppIcons.serverNetwork,
            size: 17,
            color: active ? cs.onPrimaryContainer : cs.outline,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                InstanceSwitcher._labelOf(account),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (subtitle.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: cs.outline),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (active) Icon(AppIcons.check, size: 18, color: cs.primary),
      ],
    );
  }
}
