import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_icons.dart';
import 'package:native_glass_navbar/native_glass_navbar.dart';
import '../services/screen_lock_service.dart';
import '../services/session_manager.dart';
import '../utils/theme_manager.dart';
import '../utils/auth_manager.dart';
import '../utils/snippet_manager.dart';
import '../utils/ai_manager.dart';
import '../utils/screen_lock_settings.dart';
import '../utils/terminal_settings.dart';
import '../utils/sftp_settings.dart';
import '../utils/navigation_bar_settings.dart';
import '../utils/server_view_settings.dart';
import '../utils/tab_fade_switcher.dart';
import '../widgets/floating_navigation_bar.dart';
import 'servers_screen.dart';
import 'active_sessions_screen.dart';
import 'monitoring_screen.dart';
import 'settings_screen.dart';

class MainNavigationPage extends StatefulWidget {
  final ThemeManager themeManager;
  final AuthManager authManager;
  final SnippetManager snippetManager;
  final AIManager aiManager;
  final SessionManager sessionManager;
  final TerminalSettings terminalSettings;
  final SftpSettings sftpSettings;
  final ServerViewSettings serverViewSettings;
  final NavigationBarSettings navigationBarSettings;
  final ScreenLockSettings screenLockSettings;
  final ScreenLockService screenLockService;

  const MainNavigationPage({
    super.key,
    required this.themeManager,
    required this.authManager,
    required this.snippetManager,
    required this.aiManager,
    required this.sessionManager,
    required this.terminalSettings,
    required this.sftpSettings,
    required this.serverViewSettings,
    required this.navigationBarSettings,
    required this.screenLockSettings,
    required this.screenLockService,
  });

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  final Set<String> _dismissedAttentionSessionIds = <String>{};
  final _monitoringKey = GlobalKey<MonitoringScreenState>();
  late final _tabSwitcher = TabFadeSwitcher(vsync: this);

  @override
  void initState() {
    super.initState();
    widget.sessionManager.addListener(_onSessionsChanged);
    widget.navigationBarSettings.addListener(_onNavigationBarSettingsChanged);
  }

  @override
  void dispose() {
    widget.sessionManager.removeListener(_onSessionsChanged);
    widget.navigationBarSettings.removeListener(
      _onNavigationBarSettingsChanged,
    );
    _tabSwitcher.dispose();
    super.dispose();
  }

  void _onNavigationBarSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _switchTab(int index) {
    if (index == _selectedIndex) return;
    // The sessions destination only exists while sessions are active, so index
    // 1 is the Monitoring tab otherwise. Resolve the tapped destination before
    // the fade starts, otherwise the guard below also blocks Monitoring.
    final isSessionsTab = _hasSessions && index == 1;
    _tabSwitcher.switchTab(
      canApply: () => mounted && (!isSessionsTab || _hasSessions),
      apply: () {
        if (!mounted) return;
        setState(() => _selectedIndex = index);
      },
    );
  }

  void _onSessionsChanged() {
    if (!mounted) return;

    _dismissedAttentionSessionIds.removeWhere(
      (id) =>
          !(widget.sessionManager.getSession(id)?.scriptNeedsInput ?? false),
    );

    if (!widget.sessionManager.hasActiveSessions) {
      if (_selectedIndex == 1) {
        _selectedIndex = 0;
      } else if (_selectedIndex > 1) {
        _selectedIndex -= 1;
      }
      _dismissedAttentionSessionIds.clear();
    }
    setState(() {});
    _tabSwitcher.resetFadeIfIdle();
  }

  AppSession? get _attentionSession {
    for (final session in widget.sessionManager.sessions) {
      if (session.scriptNeedsInput &&
          !_dismissedAttentionSessionIds.contains(session.sessionId)) {
        return session;
      }
    }
    return null;
  }

  bool get _hasSessions => widget.sessionManager.hasActiveSessions;

  @override
  Widget build(BuildContext context) {
    final hasSessions = _hasSessions;
    final useFloatingBar = widget.navigationBarSettings.useFloating;
    final isOnSessionsTab = hasSessions && _selectedIndex == 1;
    final attentionSession = _attentionSession;
    final activeSessionId = widget.sessionManager.activeSessionId;
    final showAttentionBanner =
        attentionSession != null &&
        !(isOnSessionsTab && activeSessionId == attentionSession.sessionId);

    final List<Widget> pages = [
      ServersScreen(
        authManager: widget.authManager,
        snippetManager: widget.snippetManager,
        sessionManager: widget.sessionManager,
        serverViewSettings: widget.serverViewSettings,
        onSwitchToSessions: () {
          if (_hasSessions) _switchTab(1);
        },
      ),
      if (hasSessions)
        ActiveSessionsScreen(
          sessionManager: widget.sessionManager,
          authManager: widget.authManager,
          snippetManager: widget.snippetManager,
          aiManager: widget.aiManager,
          terminalSettings: widget.terminalSettings,
          sftpSettings: widget.sftpSettings,
          onExitFullscreen: () => _switchTab(0),
          isVisible: isOnSessionsTab,
        ),
      MonitoringScreen(key: _monitoringKey, authManager: widget.authManager),
      SettingsScreen(
        themeManager: widget.themeManager,
        authManager: widget.authManager,
        terminalSettings: widget.terminalSettings,
        sftpSettings: widget.sftpSettings,
        serverViewSettings: widget.serverViewSettings,
        navigationBarSettings: widget.navigationBarSettings,
        screenLockSettings: widget.screenLockSettings,
        screenLockService: widget.screenLockService,
      ),
    ];

    if (_selectedIndex >= pages.length) _selectedIndex = 0;

    final monitoringIndex = hasSessions ? 2 : 1;
    final pageStack = FadeTransition(
      opacity: _tabSwitcher.opacity,
      child: IndexedStack(index: _selectedIndex, children: pages),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        if (isOnSessionsTab) {
          // Let the visible renderer handle in-session navigation (for example
          // the SFTP directory history) before leaving the sessions view.
          final handled =
              widget.sessionManager.activeSession?.handleBack?.call() ?? false;
          if (handled) return;
          _switchTab(0);
          return;
        }

        if (_selectedIndex == monitoringIndex) {
          final handled = _monitoringKey.currentState?.goBack() ?? false;
          if (handled) return;
        }

        if (_selectedIndex != 0) {
          _switchTab(0);
          return;
        }

        SystemNavigator.pop();
      },
      child: Scaffold(
        body: Column(
          children: [
            if (showAttentionBanner)
              _ScriptAttentionBanner(
                session: attentionSession,
                waitingCount: widget.sessionManager.waitingInputCount,
                onOpen: () {
                  setState(
                    () => _dismissedAttentionSessionIds.remove(
                      attentionSession.sessionId,
                    ),
                  );
                  widget.sessionManager.setActive(attentionSession.sessionId);
                  if (!isOnSessionsTab) _switchTab(1);
                },
                onDismiss: () {
                  setState(
                    () => _dismissedAttentionSessionIds.add(
                      attentionSession.sessionId,
                    ),
                  );
                },
              ),
            Expanded(
              child: showAttentionBanner
                  ? MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: pageStack,
                    )
                  : pageStack,
            ),
          ],
        ),
        bottomNavigationBar: isOnSessionsTab
            ? null
            : _buildBottomNavigationBar(context, hasSessions, useFloatingBar),
      ),
    );
  }

  Widget _buildBottomNavigationBar(
    BuildContext context,
    bool hasSessions,
    bool useFloatingBar,
  ) {
    if (useFloatingBar) {
      return _buildFloatingNavigationBar(hasSessions);
    }

    final materialNavigationBar = _buildMaterialNavigationBar(hasSessions);

    if (!Platform.isIOS) {
      return materialNavigationBar;
    }

    final sessionCount = widget.sessionManager.sessionCount;
    final waitingCount = widget.sessionManager.waitingInputCount;
    return NativeGlassNavBar(
      currentIndex: _selectedIndex,
      onTap: (index) => _switchTab(index),
      tintColor: Theme.of(context).colorScheme.primary,
      fallback: materialNavigationBar,
      tabs: [
        const NativeGlassNavBarItem(label: 'Servers', symbol: 'network'),
        if (hasSessions)
          NativeGlassNavBarItem(
            label: waitingCount > 0 ? 'Sessions · input' : 'Sessions',
            symbol: 'display',
            badgeValue: waitingCount > 0 ? '!' : '$sessionCount',
          ),
        const NativeGlassNavBarItem(label: 'Monitoring', symbol: 'chart.bar'),
        const NativeGlassNavBarItem(label: 'Settings', symbol: 'gear'),
      ],
    );
  }

  Widget _buildFloatingNavigationBar(bool hasSessions) {
    final sessionCount = widget.sessionManager.sessionCount;
    final waitingCount = widget.sessionManager.waitingInputCount;
    return FloatingNavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _switchTab,
      destinations: [
        const FloatingNavigationDestination(
          icon: AppIcons.dns,
          label: 'Servers',
        ),
        if (hasSessions)
          FloatingNavigationDestination(
            icon: AppIcons.monitorMultiple,
            label: waitingCount > 0 ? 'Sessions · input' : 'Sessions',
            badgeText: waitingCount > 0 ? '!' : '$sessionCount',
            badgeIsAlert: waitingCount > 0,
          ),
        const FloatingNavigationDestination(
          icon: AppIcons.chartBoxOutline,
          label: 'Monitoring',
        ),
        const FloatingNavigationDestination(
          icon: AppIcons.cog,
          label: 'Settings',
        ),
      ],
    );
  }

  Widget _buildMaterialNavigationBar(bool hasSessions) {
    final sessionCount = widget.sessionManager.sessionCount;
    final waitingCount = widget.sessionManager.waitingInputCount;
    final cs = Theme.of(context).colorScheme;
    final badgeColor = waitingCount > 0 ? cs.error : null;
    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) => _switchTab(index),
      destinations: [
        NavigationDestination(
          icon: Icon(AppIcons.dns),
          selectedIcon: Icon(AppIcons.dns),
          label: 'Servers',
        ),
        if (hasSessions)
          NavigationDestination(
            icon: Badge(
              label: Text(waitingCount > 0 ? '!' : '$sessionCount'),
              backgroundColor: badgeColor,
              child: Icon(AppIcons.monitorMultiple),
            ),
            selectedIcon: Badge(
              label: Text(waitingCount > 0 ? '!' : '$sessionCount'),
              backgroundColor: badgeColor,
              child: Icon(AppIcons.monitorMultiple),
            ),
            label: waitingCount > 0 ? 'Sessions · input' : 'Sessions',
          ),
        NavigationDestination(
          icon: Icon(AppIcons.chartBoxOutline),
          selectedIcon: Icon(AppIcons.chartBox),
          label: 'Monitoring',
        ),
        NavigationDestination(
          icon: Icon(AppIcons.cogOutline),
          selectedIcon: Icon(AppIcons.cog),
          label: 'Settings',
        ),
      ],
    );
  }
}

class _ScriptAttentionBanner extends StatelessWidget {
  final AppSession session;
  final int waitingCount;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  const _ScriptAttentionBanner({
    required this.session,
    required this.waitingCount,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = session.scriptName ?? 'Script';
    final more = waitingCount > 1 ? ' ${waitingCount - 1} more waiting.' : '';

    return Material(
      color: cs.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                AppIcons.alertCircle,
                size: 20,
                color: cs.onTertiaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$name on ${session.server.name} is waiting for input.$more',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: cs.onTertiaryContainer,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: onOpen,
                style: TextButton.styleFrom(
                  foregroundColor: cs.onTertiaryContainer,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Open'),
              ),
              IconButton(
                onPressed: onDismiss,
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  AppIcons.close,
                  size: 18,
                  color: cs.onTertiaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
