import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../utils/app_icons.dart';
import '../services/session_manager.dart';
import '../utils/api_exception.dart';
import '../utils/auth_manager.dart';
import '../utils/ai_manager.dart';
import '../utils/snippet_manager.dart';
import '../utils/terminal_settings.dart';
import '../utils/sftp_settings.dart';
import 'renderers/guacamole_renderer.dart';
import 'renderers/sftp_renderer.dart';
import 'renderers/terminal_renderer.dart';
import 'renderers/script_renderer.dart';
import 'sessions_overview_screen.dart';

/// Keeps the floating session pill inside the measured screen minus the safe
/// insets. The pill size is measured because action buttons and text scaling
/// can make it wider/taller than the old fixed 160x48 assumption.
@visibleForTesting
Offset clampSessionPillOffset(
  Offset position, {
  required Size pillSize,
  required Size screen,
  required EdgeInsets padding,
}) {
  final minX = padding.left;
  final maxX = math.max(minX, screen.width - padding.right - pillSize.width);
  final minY = padding.top + 4;
  final maxY = math.max(minY, screen.height - padding.bottom - pillSize.height);
  return Offset(position.dx.clamp(minX, maxX), position.dy.clamp(minY, maxY));
}

/// Hosts the sessions destination: the full-screen overview and the renderer
/// for the session that is currently open.
///
/// The overview is the default state. Opening a card shows that session
/// fullscreen; the floating pill at the top takes the user back to the
/// overview instead of opening the old bottom sheet.
class ActiveSessionsScreen extends StatefulWidget {
  final SessionManager sessionManager;
  final AuthManager authManager;
  final SnippetManager snippetManager;
  final AIManager aiManager;
  final TerminalSettings terminalSettings;
  final SftpSettings sftpSettings;

  /// Session that is currently shown fullscreen, or null for the overview.
  final String? openSessionId;
  final ValueChanged<String?> onOpenSessionChanged;

  /// Whether the sessions tab is currently visible. Script prompts are only
  /// presented for the active, visible session; background prompts are surfaced
  /// through the navigation attention banner.
  final bool isVisible;

  const ActiveSessionsScreen({
    super.key,
    required this.sessionManager,
    required this.authManager,
    required this.snippetManager,
    required this.aiManager,
    required this.terminalSettings,
    required this.sftpSettings,
    required this.openSessionId,
    required this.onOpenSessionChanged,
    this.isVisible = false,
  });

  @override
  State<ActiveSessionsScreen> createState() => ActiveSessionsScreenState();
}

class ActiveSessionsScreenState extends State<ActiveSessionsScreen> {
  static const Size _fallbackPillSize = Size(160, 48);

  double? _pillX;
  double _pillY = 0;
  final GlobalKey _pillKey = GlobalKey();
  Size _pillSize = Size.zero;
  bool _closingAll = false;
  final Map<String, GlobalKey> _previewKeys = {};
  final Map<String, Uint8List> _previews = {};

  Size get _effectivePillSize =>
      _pillSize.isEmpty ? _fallbackPillSize : _pillSize;

  void _schedulePillMeasurement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _pillKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || box.size == _pillSize) return;
      setState(() => _pillSize = box.size);
    });
  }

  @override
  void initState() {
    super.initState();
    widget.sessionManager.addListener(_onChanged);
    widget.aiManager.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.sessionManager.removeListener(_onChanged);
    widget.aiManager.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final ids = widget.sessionManager.sessions
        .map((session) => session.sessionId)
        .toSet();
    _previewKeys.removeWhere((id, _) => !ids.contains(id));
    _previews.removeWhere((id, _) => !ids.contains(id));
    setState(() {});
  }

  GlobalKey _previewKeyFor(String sessionId) {
    return _previewKeys.putIfAbsent(sessionId, () => GlobalKey());
  }

  /// Captures the visible renderer into the card preview. The boundary is only
  /// painted while the session is open, so this must run before the parent
  /// switches back to the overview.
  Future<void> _capturePreview(String? sessionId) async {
    if (sessionId == null) return;
    final boundary = _previewKeys[sessionId]?.currentContext
        ?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return;

    try {
      final image = await boundary.toImage(pixelRatio: 0.75);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted || data == null) return;
      setState(() {
        _previews[sessionId] = data.buffer.asUint8List();
      });
    } catch (error) {
      debugPrint('Could not capture session preview: $error');
    }
  }

  /// Leaves the fullscreen session and shows the overview. Called by the pill
  /// and by the system back handler.
  ///
  /// The preview capture is started before the renderer goes offstage but is
  /// deliberately not awaited: switching pages must never wait for a raster
  /// snapshot. The card updates as soon as the snapshot is ready.
  void showOverview() {
    final openId = widget.openSessionId;
    if (openId == null) return;
    unawaited(_capturePreview(openId));
    widget.onOpenSessionChanged(null);
  }

  void _openSession(String sessionId) {
    if (widget.openSessionId == sessionId) return;
    widget.sessionManager.setActive(sessionId);
    widget.onOpenSessionChanged(sessionId);
  }

  Future<bool> _closeSession(String sessionId) async {
    final token = widget.authManager.sessionToken;
    if (token == null) return false;
    final session = widget.sessionManager.getSession(sessionId);
    if (session == null) return true;

    if (session.isScriptRunning) {
      final close = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Close running script?'),
          content: Text(
            '${session.scriptName ?? 'This script'} is still running and will be interrupted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep running'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Close session'),
            ),
          ],
        ),
      );
      if (close != true) return false;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await widget.sessionManager.closeSession(sessionId, token);
      _previews.remove(sessionId);
      _previewKeys.remove(sessionId);
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyApiError(error, fallback: 'Could not close the session.'),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  /// Asks for confirmation and closes every open session. Triggered by the
  /// close-all action next to the floating navigation bar.
  Future<void> closeAllSessions() async {
    if (_closingAll) return;
    final sm = widget.sessionManager;
    final token = widget.authManager.sessionToken;
    if (token == null || sm.sessions.isEmpty) return;
    final count = sm.sessions.length;
    final runningScripts = sm.sessions
        .where((session) => session.isScriptRunning)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final cs = Theme.of(dialogCtx).colorScheme;
        return AlertDialog(
          title: const Text('Close all sessions?'),
          content: Text(
            runningScripts > 0
                ? 'Close $count sessions? $runningScripts running ${runningScripts == 1 ? 'script' : 'scripts'} will be interrupted. This cannot be undone.'
                : 'Close $count sessions? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Close all'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (!mounted || sm.sessions.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _closingAll = true);
    try {
      await sm.closeAll(token);
      _previews.clear();
      _previewKeys.clear();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to close sessions'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _closingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sm = widget.sessionManager;
    final sessions = sm.sessions;
    final openId = widget.openSessionId;
    final openIndex = openId == null
        ? -1
        : sessions.indexWhere((session) => session.sessionId == openId);
    final showingOverview = openIndex < 0;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = MediaQuery.of(context).padding;
          if (!showingOverview) {
            final pillSize = _effectivePillSize;
            _schedulePillMeasurement();
            _pillX ??= (constraints.maxWidth - pillSize.width) / 2;
            final clamped = clampSessionPillOffset(
              Offset(_pillX!, _pillY),
              pillSize: pillSize,
              screen: constraints.biggest,
              padding: padding,
            );
            _pillX = clamped.dx;
            _pillY = clamped.dy;
          }

          return Stack(
            children: [
              Positioned.fill(
                child: IndexedStack(
                  index: showingOverview ? sessions.length : openIndex,
                  children: [
                    for (final session in sessions) _buildRenderer(session),
                    SessionsOverviewScreen(
                      sessionManager: sm,
                      previews: _previews,
                      onOpenSession: _openSession,
                      onCloseSession: _closeSession,
                    ),
                  ],
                ),
              ),
              if (!showingOverview)
                Positioned(
                  left: _pillX,
                  top: _pillY,
                  child: _buildDraggablePill(sessions, openId, constraints),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDraggablePill(
    List<AppSession> sessions,
    String? activeId,
    BoxConstraints constraints,
  ) {
    final cs = Theme.of(context).colorScheme;
    final padding = MediaQuery.of(context).padding;
    final active = sessions.firstWhere(
      (s) => s.sessionId == activeId,
      orElse: () => sessions.first,
    );

    final pillSize = _effectivePillSize;
    return GestureDetector(
      key: _pillKey,
      onPanUpdate: (d) {
        setState(() {
          final clamped = clampSessionPillOffset(
            Offset(_pillX! + d.delta.dx, _pillY + d.delta.dy),
            pillSize: pillSize,
            screen: constraints.biggest,
            padding: padding,
          );
          _pillX = clamped.dx;
          _pillY = clamped.dy;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'All sessions',
              child: GestureDetector(
                onTap: showOverview,
                behavior: HitTestBehavior.opaque,
                child: Semantics(
                  button: true,
                  label: 'Show all sessions',
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              _iconForSession(active),
                              size: 14,
                              color: cs.primary,
                            ),
                            if (active.scriptNeedsInput)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: cs.error,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 5),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 80),
                          child: Text(
                            active.isScriptSession
                                ? (active.scriptName ?? 'Script')
                                : active.server.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (sessions.length > 1) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${sessions.length}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 2),
                        Icon(AppIcons.chevronDown, size: 14, color: cs.outline),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            if (active.showMenu != null || active.showSnippets != null) ...[
              Container(
                width: 1,
                height: 22,
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),

              GestureDetector(
                onTap: () {
                  if (active.showSnippets != null) {
                    active.showSnippets!();
                  } else {
                    active.showMenu?.call();
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Icon(
                    active.showSnippets != null
                        ? AppIcons.codeBraces
                        : AppIcons.toolbox,
                    size: 16,
                    color: cs.primary,
                  ),
                ),
              ),
            ],

            if (active.showAI != null && widget.aiManager.isAvailable) ...[
              Container(
                width: 1,
                height: 22,
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),

              GestureDetector(
                onTap: () => active.showAI?.call(),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Icon(AppIcons.creation, size: 16, color: cs.primary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRenderer(AppSession session) {
    final token = widget.authManager.sessionToken ?? '';
    session.onCallbacksReady = _onChanged;
    final Widget renderer;
    if (session.isScriptSession) {
      renderer = ScriptRenderer(
        key: ValueKey('script_${session.sessionId}'),
        session: session,
        token: token,
        sessionManager: widget.sessionManager,
        terminalSettings: widget.terminalSettings,
        isVisible:
            widget.isVisible && widget.openSessionId == session.sessionId,
      );
    } else {
      renderer = switch (session.type) {
        ConnectionType.guacamole => GuacamoleRenderer(
          key: ValueKey('guac_${session.sessionId}'),
          session: session,
          token: token,
          sessionManager: widget.sessionManager,
        ),
        ConnectionType.terminal => TerminalRenderer(
          key: ValueKey('term_${session.sessionId}'),
          session: session,
          token: token,
          sessionManager: widget.sessionManager,
          snippetManager: widget.snippetManager,
          aiManager: widget.aiManager,
          terminalSettings: widget.terminalSettings,
        ),
        ConnectionType.sftp => SftpRenderer(
          key: ValueKey('sftp_${session.sessionId}'),
          session: session,
          token: token,
          sessionManager: widget.sessionManager,
          sftpSettings: widget.sftpSettings,
        ),
      };
    }
    return RepaintBoundary(
      key: _previewKeyFor(session.sessionId),
      child: renderer,
    );
  }

  IconData _iconForSession(AppSession session) {
    if (session.isScriptSession) return AppIcons.codeBracesBox;
    return _iconForType(session.type);
  }

  IconData _iconForType(ConnectionType type) {
    switch (type) {
      case ConnectionType.guacamole:
        return AppIcons.monitorSmall;
      case ConnectionType.terminal:
        return AppIcons.console;
      case ConnectionType.sftp:
        return AppIcons.folderOutline;
    }
  }
}
