import 'package:flutter/material.dart';

import '../../models/server.dart';
import '../../services/server_actions_service.dart';
import '../../utils/api_exception.dart';
import '../../utils/app_icons.dart';
import '../../widgets/app_ui.dart';

/// Edits the note of [server]. Resolves to true when the note was saved.
Future<bool?> showServerNotesSheet(
  BuildContext context, {
  required Server server,
  required String token,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ServerNotesSheet(server: server, token: token),
  );
}

class ServerNotesSheet extends StatefulWidget {
  final Server server;
  final String token;

  const ServerNotesSheet({
    super.key,
    required this.server,
    required this.token,
  });

  @override
  State<ServerNotesSheet> createState() => _ServerNotesSheetState();
}

class _ServerNotesSheetState extends State<ServerNotesSheet> {
  final _controller = TextEditingController();
  bool _showInList = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ServerActionsService.getNotes(
        widget.token,
        widget.server.id,
      );
      if (!mounted) return;
      setState(() {
        _controller.text = data.notes;
        _showInList = data.showInList;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(e, fallback: 'Could not load the note.');
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ServerActionsService.setNotes(
        token: widget.token,
        entryId: widget.server.id,
        notes: _controller.text,
        showInList: _showInList,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(e, fallback: 'Could not save the note.');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppSheetHandle(),
            AppSheetTitle(
              title: 'Notes',
              subtitle: widget.server.name,
              icon: AppIcons.noteEdit,
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _controller,
                      minLines: 4,
                      maxLines: 10,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Write a note about this server…',
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.control),
                          borderSide: appBorderSide(cs),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.control),
                          borderSide: appBorderSide(cs),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show first line in server list'),
                      value: _showInList,
                      onChanged: (v) => setState(() => _showInList = v),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(color: cs.error, fontSize: 12.5),
                        ),
                      ),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.control),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
