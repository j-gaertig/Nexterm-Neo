import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/nexterm_api.dart';
import '../../settings/settings_widgets.dart';

/// Authorize another device (web DeviceLinkDialog equivalent):
/// enter the `XXXX-XXXX` code shown on the other device, review it,
/// approve it.
class SettingsLinkDevicePage extends StatefulWidget {
  const SettingsLinkDevicePage(
      {super.key,
      required this.api,
      required this.token,
      this.onSessionExpired});

  final NextermApi api;
  final String token;
  final VoidCallback? onSessionExpired;

  @override
  State<SettingsLinkDevicePage> createState() =>
      _SettingsLinkDevicePageState();
}

class _SettingsLinkDevicePageState
    extends State<SettingsLinkDevicePage> {
  final _code = TextEditingController();
  Map<String, dynamic>? _info;
  String? _error;
  bool _working = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String get _normalized =>
      _code.text.trim().toUpperCase().replaceAll(' ', '');

  Future<void> _lookup() async {
    final code = _normalized;
    if (!RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4}$').hasMatch(code)) {
      setState(
          () => _error = 'Code must look like XXXX-XXXX.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
      _info = null;
    });
    try {
      final info = await widget.api
          .fetchDeviceCodeInfo(widget.token, code);
      if (!mounted) return;
      setState(() {
        _info = info;
        _working = false;
      });
    } on SessionExpiredException {
      widget.onSessionExpired?.call();
    } on NextermApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _working = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Lookup failed.';
        _working = false;
      });
    }
  }

  Future<void> _authorize() async {
    final code = _normalized;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.api
          .authorizeDeviceCode(widget.token, code);
      if (!mounted) return;
      setState(() {
        _working = false;
        _info = null;
      });
      _code.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device authorized.')),
      );
    } on SessionExpiredException {
      widget.onSessionExpired?.call();
    } on NextermApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _working = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Authorization failed.';
        _working = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Link device')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter the code shown on the other device to link it to your account.',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              autofocus: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Link code',
                hintText: 'XXXX-XXXX',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _lookup(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _working ? null : _lookup,
              style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 16)),
              child: _working
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2))
                  : const Text('Look up device'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(
                      color:
                          Theme.of(context).colorScheme.error)),
            ],
            if (_info != null) ...[
              const SizedBox(height: 16),
              SettingsGroup(
                title: 'Device',
                children: [
                  for (final row in _infoRows(_info!))
                    ListTile(
                      title: Text(row.$1,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                      subtitle: SelectableText(row.$2,
                          style: const TextStyle(fontSize: 12)),
                      trailing: row.$1 == 'Code'
                          ? IconButton(
                              icon: const Icon(
                                  Icons.copy_outlined,
                                  size: 18),
                              tooltip: 'Copy',
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(
                                        text: row.$2));
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Copied.')),
                                );
                              },
                            )
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _working ? null : _authorize,
                icon: const Icon(Icons.link),
                label: const Text('Authorize this device'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

List<(String, String)> _infoRows(Map<String, dynamic> info) {
  String str(Object? v) => v == null ? '—' : '$v';
  return [
    ('Client', str(info['clientType'] ?? info['client'])),
    ('IP address', str(info['ip'] ?? info['ipAddress'])),
    ('Browser', str(info['userAgent'])),
    ('Created', str(info['createdAt'] ?? info['timestamp'])),
  ];
}
