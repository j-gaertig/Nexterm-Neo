import 'package:flutter/material.dart';

import '../../models/server.dart';
import '../../services/server_actions_service.dart';
import '../../utils/api_exception.dart';
import '../../utils/app_icons.dart';
import '../../utils/tag_color.dart';
import '../../widgets/app_ui.dart';

/// Toggles tags on [server]. Resolves to true when anything changed.
Future<bool?> showServerTagsSheet(
  BuildContext context, {
  required Server server,
  required String token,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ServerTagsSheet(server: server, token: token),
  );
}

class ServerTagsSheet extends StatefulWidget {
  final Server server;
  final String token;

  const ServerTagsSheet({super.key, required this.server, required this.token});

  @override
  State<ServerTagsSheet> createState() => _ServerTagsSheetState();
}

class _ServerTagsSheetState extends State<ServerTagsSheet> {
  List<Tag> _tags = [];
  late final Set<int> _assigned = {
    for (final t in widget.server.tags ?? const <Tag>[]) t.id,
  };
  final Set<int> _busy = {};
  bool _loading = true;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tags = await ServerActionsService.listTags(widget.token);
      if (!mounted) return;
      setState(() {
        _tags = tags;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(e, fallback: 'Could not load tags.');
        _loading = false;
      });
    }
  }

  Future<void> _toggle(Tag tag) async {
    if (_busy.contains(tag.id)) return;
    final assign = !_assigned.contains(tag.id);
    setState(() {
      _busy.add(tag.id);
      _error = null;
    });
    try {
      if (assign) {
        await ServerActionsService.assignTag(
          widget.token,
          tag.id,
          widget.server.id,
        );
      } else {
        await ServerActionsService.removeTag(
          widget.token,
          tag.id,
          widget.server.id,
        );
      }
      if (!mounted) return;
      setState(() {
        assign ? _assigned.add(tag.id) : _assigned.remove(tag.id);
        _changed = true;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = friendlyApiError(e, fallback: 'Could not update tag.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(tag.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppSheetHandle(),
            AppSheetTitle(
              title: 'Tags',
              subtitle: widget.server.name,
              icon: AppIcons.tag,
              trailing: TextButton(
                onPressed: () => Navigator.pop(context, _changed),
                child: const Text('Done'),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_tags.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Text(
                  _error ?? 'No tags yet. Create tags in the web client.',
                  style: TextStyle(color: cs.outline),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in _tags)
                      FilterChip(
                        selected: _assigned.contains(tag.id),
                        showCheckmark: true,
                        side: appBorderSide(cs),
                        avatar: CircleAvatar(
                          radius: 6,
                          backgroundColor: parseTagColor(
                            tag.color,
                            fallback: cs.outline,
                          ),
                        ),
                        label: Text(tag.name),
                        onSelected: _busy.contains(tag.id)
                            ? null
                            : (_) => _toggle(tag),
                      ),
                  ],
                ),
              ),
            if (_error != null && _tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(_error!, style: TextStyle(color: cs.error)),
              ),
          ],
        ),
      ),
    );
  }
}
