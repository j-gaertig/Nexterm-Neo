import 'package:flutter/material.dart';

import '../../models/managed_identity.dart';
import '../../models/server.dart';
import '../../services/server_editor_service.dart';
import '../../utils/api_exception.dart';
import '../../utils/app_icons.dart';
import '../../widgets/app_ui.dart';

/// Lets the user pick which identity to use when a server has several.
/// Resolves to the identity id, or `null` when the sheet is dismissed.
Future<int?> showIdentityPickerSheet(
  BuildContext context, {
  required Server server,
  required String token,
  String title = 'Choose identity',
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        IdentityPickerSheet(server: server, token: token, title: title),
  );
}

class IdentityPickerSheet extends StatefulWidget {
  final Server server;
  final String token;
  final String title;

  const IdentityPickerSheet({
    super.key,
    required this.server,
    required this.token,
    required this.title,
  });

  @override
  State<IdentityPickerSheet> createState() => _IdentityPickerSheetState();
}

class _IdentityPickerSheetState extends State<IdentityPickerSheet> {
  Map<int, ManagedIdentity> _identities = {};
  bool _loading = true;
  String? _error;

  List<int> get _ids => widget.server.identities ?? const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await ServerEditorService.getIdentities(widget.token);
      if (!mounted) return;
      final wanted = _ids.toSet();
      setState(() {
        _identities = {
          for (final identity in all)
            if (wanted.contains(int.tryParse(identity.id.toString())))
              int.parse(identity.id.toString()): identity,
        };
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(e, fallback: 'Could not load identities.');
        _loading = false;
      });
    }
  }

  String _label(int id) {
    final identity = _identities[id];
    if (identity == null) return 'Identity #$id';
    if (identity.name.trim().isNotEmpty) return identity.name;
    if (identity.username.trim().isNotEmpty) return identity.username;
    return 'Identity #$id';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppSheetHandle(),
            AppSheetTitle(
              title: widget.title,
              subtitle: widget.server.name,
              icon: AppIcons.account,
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(_error!, style: TextStyle(color: cs.error)),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: _ids.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final id = _ids[i];
                    final identity = _identities[id];
                    final username = identity?.username.trim() ?? '';
                    return AppCard(
                      onSheet: true,
                      radius: AppRadii.control,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      onTap: () => Navigator.pop(context, id),
                      child: Row(
                        children: [
                          const AppIconBox(icon: AppIcons.key, size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _label(id),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (username.isNotEmpty)
                                  Text(
                                    username,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.outline,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          Icon(
                            AppIcons.chevronRight,
                            size: 18,
                            color: cs.outline,
                          ),
                        ],
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
}
