import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_icons.dart';
import '../services/screen_lock_service.dart';
import '../services/session_manager.dart';
import '../utils/theme_manager.dart';
import '../utils/auth_manager.dart';
import '../utils/snippet_manager.dart';
import '../utils/ai_manager.dart';
import '../utils/screen_lock_settings.dart';
import '../utils/terminal_settings.dart';
import '../utils/sftp_settings.dart';
import '../utils/server_view_settings.dart';
import '../widgets/floating_navigation_bar.dart';
import '../widgets/nav_scope.dart';
import '../widgets/tab_crossfade.dart';
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
    required this.screenLockSettings,
    required this.screenLockService,
  });

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;
  bool _hadSessions = false;
  String? _openSessionId;
  final Set<String> _dismissedAttentionSessionIds = <String>{};
  final _monitoringKey = GlobalKey<MonitoringScreenState>();
  final _sessionsKey = GlobalKey<ActiveSessionsScreenState>();
  final _serversKey = GlobalKey<ServersScreenState>();
  final _serversNavKey = GlobalKey<NavigatorState>();
  final _settingsNavKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _hadSessions = widget.sessionManager.hasActiveSessions;
    widget.sessionManager.addListener(_onSessionsChanged);
  }

  @override
  void dispose() {
    widget.sessionManager.removeListener(_onSessionsChanged);
    super.dispose();
  }

  /// Navigator of the tab at [index], or null for tabs without sub pages.
  GlobalKey<NavigatorState>? _tabNavigatorKey(int index) {
    if (index == 0) return _serversNavKey;
    if (index == _lastTabIndex) return _settingsNavKey;
    return null;
  }

  int get _lastTabIndex => _hasSessions ? 3 : 2;

  int get monitoringIndex => _hasSessions ? 2 : 1;

  /// Pops one page of the tab at [index]. Returns true when a page was closed.
  bool _popTabPage(int index) {
    final navigator = _tabNavigatorKey(index)?.currentState;
    if (navigator == null || !navigator.canPop()) return false;
    navigator.pop();
    return true;
  }

  void _switchTab(int index) {
    if (index == _selectedIndex) {
      // Tapping the active destination again goes one step back inside it.
      if (_popTabPage(index)) return;
      if (index == monitoringIndex &&
          _monitoringKey.currentState?.goBack() == true) {
        return;
      }
      // Pressing the Sessions destination again always returns to the
      // overview instead of re-opening the last session.
      if (index == 1 && _openSessionId != null) {
        setState(() => _openSessionId = null);
      }
      return;
    }
    setState(() {
      _selectedIndex = index;
      _openSessionId = null;
    });
  }

  void _openSession(String sessionId) {
    widget.sessionManager.setActive(sessionId);
    setState(() {
      _selectedIndex = 1;
      _openSessionId = sessionId;
    });
    // A new session can insert the Sessions destination in the same frame
    // (and script sessions notify again while starting). Re-assert the target
    // once the dust has settled so the new session always ends up on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.sessionManager.getSession(sessionId) == null) {
        return;
      }
      if (_openSessionId != sessionId || _selectedIndex != 1) {
        setState(() {
          _selectedIndex = 1;
          _openSessionId = sessionId;
        });
      }
    });
  }

  void _onSessionsChanged() {
    if (!mounted) return;

    if (_openSessionId != null &&
        widget.sessionManager.getSession(_openSessionId!) == null) {
      _openSessionId = null;
    }

    _dismissedAttentionSessionIds.removeWhere(
      (id) =>
          !(widget.sessionManager.getSession(id)?.scriptNeedsInput ?? false),
    );

    final hasSessions = widget.sessionManager.hasActiveSessions;
    if (!hasSessions) _openSessionId = null;
    if (_hadSessions && !hasSessions) {
      // The Sessions destination disappeared. Keep the user on the same
      // logical tab instead of silently jumping to a different one.
      if (_selectedIndex == 1) {
        _selectedIndex = 0;
      } else if (_selectedIndex > 1) {
        _selectedIndex -= 1;
      }
      _dismissedAttentionSessionIds.clear();
    } else if (!_hadSessions && hasSessions && _selectedIndex >= 1) {
      // The Sessions destination was inserted at index 1.
      _selectedIndex += 1;
    }
    _hadSessions = hasSessions;

    setState(() {});
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
    final isOnSessionsTab = hasSessions && _selectedIndex == 1;
    final isInSession = isOnSessionsTab && _openSessionId != null;
    final attentionSession = _attentionSession;
    final activeSessionId = widget.sessionManager.activeSessionId;
    final showAttentionBanner =
        attentionSession != null &&
        !(isInSession && activeSessionId == attentionSession.sessionId);

    // Stable page keys let TabCrossfade keep each page's state attached to the
    // page itself when the Sessions destination is inserted or removed.
    final List<Widget> pages = [
      KeyedSubtree(
        key: const ValueKey('tab-page-servers'),
        child: TabNavigator(
          navigatorKey: _serversNavKey,
          builder: (_) => ServersScreen(
            key: _serversKey,
            authManager: widget.authManager,
            snippetManager: widget.snippetManager,
            sessionManager: widget.sessionManager,
            serverViewSettings: widget.serverViewSettings,
            onSessionOpened: (sessionId) {
              if (_hasSessions) _openSession(sessionId);
            },
          ),
        ),
      ),
      if (hasSessions)
        KeyedSubtree(
          key: const ValueKey('tab-page-sessions'),
          child: ActiveSessionsScreen(
            key: _sessionsKey,
            sessionManager: widget.sessionManager,
            authManager: widget.authManager,
            snippetManager: widget.snippetManager,
            aiManager: widget.aiManager,
            terminalSettings: widget.terminalSettings,
            sftpSettings: widget.sftpSettings,
            openSessionId: _openSessionId,
            onOpenSessionChanged: (sessionId) {
              setState(() => _openSessionId = sessionId);
            },
            isVisible: isOnSessionsTab,
          ),
        ),
      KeyedSubtree(
        key: const ValueKey('tab-page-monitoring'),
        child: MonitoringScreen(
          key: _monitoringKey,
          authManager: widget.authManager,
        ),
      ),
      KeyedSubtree(
        key: const ValueKey('tab-page-settings'),
        child: TabNavigator(
          navigatorKey: _settingsNavKey,
          builder: (_) => SettingsScreen(
            themeManager: widget.themeManager,
            authManager: widget.authManager,
            terminalSettings: widget.terminalSettings,
            sftpSettings: widget.sftpSettings,
            serverViewSettings: widget.serverViewSettings,
            screenLockSettings: widget.screenLockSettings,
            screenLockService: widget.screenLockService,
          ),
        ),
      ),
    ];

    if (_selectedIndex >= pages.length) _selectedIndex = 0;

    // Like T3 Code, the One UI bar disappears while the keyboard is open and
    // while a fullscreen session is on screen. The overview keeps the bar so
    // it behaves like every other top-level page.
    final showNavigationBar =
        !isInSession && MediaQuery.viewInsetsOf(context).bottom == 0;

    final theme = Theme.of(context);
    final pageTheme = showNavigationBar
        ? theme.copyWith(
            snackBarTheme: theme.snackBarTheme.copyWith(
              behavior: SnackBarBehavior.floating,
              insetPadding: const EdgeInsets.fromLTRB(
                16,
                0,
                16,
                FloatingNavigationBar.contentInset + 8,
              ),
            ),
          )
        : theme;

    return Theme(
      // The theme wraps the whole shell so that snack bars shown by the shell's
      // own Scaffold also float above the navigation bar.
      data: pageTheme,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;

          if (isInSession) {
            // Let the visible renderer handle in-session navigation (for example
            // the SFTP directory history) before returning to the overview.
            final session = _openSessionId == null
                ? null
                : widget.sessionManager.getSession(_openSessionId!);
            final handled = session?.handleBack?.call() ?? false;
            if (handled) return;
            _sessionsKey.currentState?.showOverview();
            return;
          }

          if (isOnSessionsTab) {
            _switchTab(0);
            return;
          }

          if (_popTabPage(_selectedIndex)) return;

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
          body: Stack(
            fit: StackFit.expand,
            children: [
              Column(
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
                        _openSession(attentionSession.sessionId);
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
                    child: FloatingNavigationBarInset(
                      bottom: showNavigationBar
                          ? FloatingNavigationBar.contentInset
                          : 0,
                      child: Theme(
                        data: pageTheme,
                        // Resolve the MediaQuery below the Scaffold: it has
                        // already consumed the keyboard inset, so forwarding the
                        // one from above the Scaffold would make the pages' own
                        // Scaffolds subtract the keyboard height a second time.
                        child: Builder(
                          builder: (context) {
                            Widget stack = TabCrossfade(
                              index: _selectedIndex,
                              // Swiping works between the top-level pages, but
                              // not while a fullscreen session or the keyboard is
                              // open. The edge destinations only move inwards.
                              swipeEnabled: showNavigationBar && !isInSession,
                              onSwipeIndexChanged: _switchTab,
                              children: pages,
                            );
                            if (showAttentionBanner) {
                              stack = MediaQuery(
                                data: MediaQuery.of(
                                  context,
                                ).removePadding(removeTop: true),
                                child: stack,
                              );
                            }
                            return stack;
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (showNavigationBar)
                Positioned(
                  key: const ValueKey('floating-navigation-overlay'),
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildNavigationBar(hasSessions),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<FloatingNavigationDestination> _destinations(bool hasSessions) {
    final sessionCount = widget.sessionManager.sessionCount;
    final waitingCount = widget.sessionManager.waitingInputCount;
    return [
      const FloatingNavigationDestination(icon: AppIcons.dns, label: 'Servers'),
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
    ];
  }

  Widget _buildNavigationBar(bool hasSessions) {
    return FloatingNavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _switchTab,
      trailing: _buildNavigationAction(),
      destinations: _destinations(hasSessions),
    );
  }

  /// Page-specific action shown to the right of the navigation bar.
  ///
  /// Servers adds a server, the sessions overview closes all sessions, and the
  /// other destinations have no action of their own.
  Widget? _buildNavigationAction() {
    if (_selectedIndex == 0) {
      return FloatingNavigationAction(
        icon: AppIcons.plus,
        tooltip: 'Add server',
        onPressed: () => _serversKey.currentState?.createServer(),
      );
    }

    if (_hasSessions && _selectedIndex == 1 && _openSessionId == null) {
      return FloatingNavigationAction(
        icon: AppIcons.close,
        tooltip: 'Close all sessions',
        destructive: true,
        onPressed: () => _sessionsKey.currentState?.closeAllSessions(),
      );
    }

    return null;
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
