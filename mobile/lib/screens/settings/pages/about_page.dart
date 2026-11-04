import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/account_service.dart';
import '../../../services/api_config.dart';
import '../../../utils/api_client.dart';
import '../../../utils/app_icons.dart';
import '../../../widgets/app_ui.dart';
import '../ui.dart';

/// App and server information, links and open-source licenses.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String? _serverVersion;
  bool _loadingVersion = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final version = await AccountService.getServerVersion();
    if (!mounted) return;
    setState(() {
      _serverVersion = version;
      _loadingVersion = false;
    });
  }

  Future<void> _open(String url) async {
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) settingsToast(context, 'Could not open the link.');
    } catch (_) {
      if (mounted) settingsToast(context, 'Could not open the link.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final instance = ApiConfig.baseUrl
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'/api/?$'), '');
    return SettingsPage(
      title: 'About',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: appBorderColor(cs)),
                ),
                child: Icon(
                  AppIcons.console,
                  size: 34,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Nexterm Neo',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                'Server management on the go',
                style: tt.bodySmall?.copyWith(color: cs.outline),
              ),
            ],
          ),
        ),
        SettingsGroup(
          title: 'Version',
          children: [
            SettingsTile(
              icon: AppIcons.cellphone,
              title: 'App',
              chevron: false,
              trailing: Text(
                ApiClient.appVersion,
                style: TextStyle(
                  color: cs.outline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SettingsTile(
              icon: AppIcons.dns,
              title: 'Server',
              subtitle: instance,
              chevron: false,
              trailing: _loadingVersion
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _serverVersion ?? 'Unknown',
                      style: TextStyle(
                        color: cs.outline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: instance));
                if (context.mounted) {
                  settingsToast(context, 'Server address copied.');
                }
              },
            ),
          ],
        ),
        SettingsGroup(
          title: 'Project',
          children: [
            SettingsTile(
              icon: AppIcons.codeBraces,
              title: 'Nexterm Neo on GitHub',
              subtitle: 'Source code of this fork',
              onTap: () => _open('https://github.com/j-gaertig/Nexterm-Neo'),
            ),
            SettingsTile(
              icon: AppIcons.web,
              title: 'Nexterm (original project)',
              subtitle: 'gnmyt/Nexterm',
              onTap: () => _open('https://github.com/gnmyt/Nexterm'),
            ),
            SettingsTile(
              icon: AppIcons.informationOutline,
              title: 'Open-source licenses',
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Nexterm Neo',
                applicationVersion: ApiClient.appVersion,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Nexterm Neo is an unofficial community fork and is not affiliated '
            'with the official Nexterm project.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.outline, height: 1.4),
          ),
        ),
      ],
    );
  }
}
