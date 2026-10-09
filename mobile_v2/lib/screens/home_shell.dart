import 'package:flutter/material.dart';

import '../account/account_models.dart';
import '../auth/session_store.dart';
import '../monitoring/monitoring_repository.dart';
import '../remote/session_opener.dart';
import '../servers/server_models.dart';
import '../servers/server_repository.dart';
import '../api/nexterm_api.dart';
import '../settings/app_settings.dart';
import '../settings/settings_scope.dart';
import '../widgets/wobbly_nav_bar.dart';
import 'pages/home_page.dart';
import 'pages/monitoring_page.dart';
import 'pages/more_page.dart';
import 'pages/servers_page.dart';
import 'pages/settings_page.dart';

/// Main shell after login: 5 pages + WobblyNavBar.
///
/// Order (left → right): Servers, Monitoring, Home (default),
/// More, Settings.
class HomeShell extends StatefulWidget {
  const HomeShell(
      {super.key,
      required this.session,
      required this.onLogout,
      required this.settings,
      this.serversRepository,
      this.monitoringRepository,
      this.recentsLoader,
      this.moreLoader,
      this.settingsProfileLoader,
      this.settingsSessionsLoader});

  final SessionInfo session;
  final VoidCallback onLogout;
  final AppSettings settings;

  /// Test seam: avoids real HTTP in widget tests.
  final ServerRepository? serversRepository;

  /// Test seam: avoids real HTTP in widget tests.
  final MonitoringRepository? monitoringRepository;

  /// Test seam: recents loader for the home page.
  final Future<List<ServerEntry>> Function()? recentsLoader;

  /// Test seam: library loader for the more page.
  final Future<MoreData> Function()? moreLoader;

  /// Test seams: profile + sessions loaders for settings.
  final Future<UserInfo> Function()? settingsProfileLoader;
  final Future<List<LoginSession>> Function()? settingsSessionsLoader;

  @visibleForTesting
  static const int defaultIndex = 2;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final PageController _controller;
  late final ServerRepository _serversRepository;
  late final SessionOpener _opener;
  late final MonitoringRepository _monitoringRepository;
  int _index = HomeShell.defaultIndex;

  static const _items = [
    WobblyNavItem(
        icon: Icons.dns_outlined,
        selectedIcon: Icons.dns,
        label: 'Servers'),
    WobblyNavItem(
        icon: Icons.bar_chart_outlined,
        selectedIcon: Icons.bar_chart,
        label: 'Monitoring'),
    WobblyNavItem(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: 'Home'),
    WobblyNavItem(
        icon: Icons.grid_view_outlined,
        selectedIcon: Icons.grid_view,
        label: 'More'),
    WobblyNavItem(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: _index);
    final api = NextermApi(baseUrl: widget.session.baseUrl);
    _serversRepository = widget.serversRepository ??
        ApiServerRepository(api: api, token: widget.session.token);
    _opener = SessionOpener(api: api, token: widget.session.token);
    _monitoringRepository = widget.monitoringRepository ??
        ApiMonitoringRepository(
            api: api, token: widget.session.token);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      settings: widget.settings,
      child: Scaffold(
      body: PageView(
        controller: _controller,
        onPageChanged: (index) => setState(() => _index = index),
        children: [
          ServersPage(
            repository: _serversRepository,
            api: NextermApi(baseUrl: widget.session.baseUrl),
            token: widget.session.token,
            connections: _opener,
            initialGridView: widget.settings.serversGridDefault,
            onSessionExpired: widget.onLogout,
          ),
          MonitoringPage(
            repository: _monitoringRepository,
            onSessionExpired: widget.onLogout,
            autoRefresh: widget.settings.monitoringAutoRefresh,
            refreshInterval: Duration(
                seconds: widget.settings.monitoringIntervalSec),
          ),
          HomePage(
            api: NextermApi(baseUrl: widget.session.baseUrl),
            token: widget.session.token,
            label: widget.session.label,
            loadRecents: widget.recentsLoader,
            onSessionExpired: widget.onLogout,
          ),
          MorePage(
            api: NextermApi(baseUrl: widget.session.baseUrl),
            token: widget.session.token,
            loader: widget.moreLoader,
            onSessionExpired: widget.onLogout,
          ),
          SettingsPage(
            session: widget.session,
            api: NextermApi(baseUrl: widget.session.baseUrl),
            token: widget.session.token,
            onLogout: widget.onLogout,
            settings: widget.settings,
            loadProfile: widget.settingsProfileLoader,
            loadSessions: widget.settingsSessionsLoader,
            onSessionExpired: widget.onLogout,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.only(left: 16, right: 16, bottom: 12),
          child: WobblyNavBar(
            items: _items,
            selectedIndex: _index,
            onTap: _goTo,
          ),
        ),
      ),
      ),
    );
  }
}
