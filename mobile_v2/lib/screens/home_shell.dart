import 'package:flutter/material.dart';

import '../auth/session_store.dart';
import '../widgets/wobbly_nav_bar.dart';
import 'pages/monitoring_page.dart';
import 'pages/placeholder_page.dart';
import 'pages/servers_page.dart';
import 'pages/settings_page.dart';

/// Main shell after login: 5 pages + WobblyNavBar.
///
/// Order (left → right): Servers, Monitoring, Home (default),
/// More, Settings.
class HomeShell extends StatefulWidget {
  const HomeShell(
      {super.key, required this.session, required this.onLogout});

  final SessionInfo session;
  final VoidCallback onLogout;

  @visibleForTesting
  static const int defaultIndex = 2;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final PageController _controller;
  int _index = HomeShell.defaultIndex;

  static const _items = [
    WobblyNavItem(
        icon: Icons.dns_outlined,
        selectedIcon: Icons.dns,
        label: 'Servers'),
    WobblyNavItem(
        icon: Icons.monitor_heart_outlined,
        selectedIcon: Icons.monitor_heart,
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
    return Scaffold(
      body: PageView(
        controller: _controller,
        onPageChanged: (index) => setState(() => _index = index),
        children: [
          const ServersPage(),
          const MonitoringPage(),
          PlaceholderPage(
            icon: Icons.home,
            title: 'Home',
            subtitle: 'Connected to ${widget.session.label}.',
          ),
          const PlaceholderPage(
            icon: Icons.grid_view,
            title: 'More',
            subtitle: 'Snippets, scripts and more will appear here.',
          ),
          SettingsPage(
              session: widget.session, onLogout: widget.onLogout),
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
    );
  }
}
