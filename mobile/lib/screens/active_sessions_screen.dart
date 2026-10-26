import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../utils/app_icons.dart';

import '../services/session_manager.dart';
import '../models/script_runtime.dart';
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

class ActiveSessionsScreen extends StatefulWidget {
  final SessionManager sessionManager;
  final AuthManager authManager;
  final SnippetManager snippetManager;
  final AIManager aiManager;
  final TerminalSettings terminalSettings;
  final SftpSettings sftpSettings;
  final VoidCallback? onExitFullscreen;

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
    this.onExitFullscreen,
    this.isVisible = false,
  });

  @override
  State<ActiveSessionsScreen> createState() => _ActiveSessionsScreenState();
}

class _ActiveSessionsScreenState extends State<ActiveSessionsScreen> {
  static const Size _fallbackPillSize = Size(160, 48);

  double? _pillX;
  double _pillY = 0;
  final GlobalKey _pillKey = GlobalKey();
  Size _pillSize = Size.zero;
  final ValueNotifier<bool> _closingAll = ValueNotifier(false);

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
    _closingAll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _closeSession(
    String sessionId, {
    BuildContext? dialogContext,
  }) async {
    final token = widget.authManager.sessionToken;
    if (token == null) return false;
    final session = widget.sessionManager.getSession(sessionId);
    if (session == null) return true;

    if (session.isScriptRunning) {
      final close = await showDialog<bool>(
        context: dialogContext ?? context,
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

  Future<void> _closeAllSessions(BuildContext sheetContext) async {
    if (_closingAll.value) return;
    final sm = widget.sessionManager;
    final token = widget.authManager.sessionToken;
    if (token == null || sm.sessions.isEmpty) return;
    final count = sm.sessions.length;
    final runningScripts = sm.sessions
        .where((session) => session.isScriptRunning)
        .length;
    final confirmed = await showDialog<bool>(
      context: sheetContext,
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
    _closingAll.value = true;
    try {
      await sm.closeAll(token);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to close sessions'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) _closingAll.value = false;
    }
    if (sheetContext.mounted) {
      Navigator.pop(sheetContext);
    }
  }

  void _showSessionSwitcher() {
    final sm = widget.sessionManager;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ValueListenableBuilder<bool>(
        valueListenable: _closingAll,
        builder: (_, closing, __) => ListenableBuilder(
          listenable: sm,
          builder: (_, __) => _SessionSwitcherSheet(
            sessions: sm.sessions,
            activeSessionId: sm.activeSessionId,
            isClosingAll: closing,
            onSelect: (id) {
              if (closing) return;
              sm.setActive(id);
              Navigator.pop(ctx);
            },
            onClose: (id) async {
              if (closing) return;
              final closed = await _closeSession(id, dialogContext: ctx);
              if (closed && sm.sessions.isEmpty && ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            onCloseAll: sm.sessions.length > 1
                ? () => _closeAllSessions(ctx)
                : null,
            onExitFullscreen: widget.onExitFullscreen != null
                ? () {
                    if (closing) return;
                    Navigator.pop(ctx);
                    widget.onExitFullscreen!();
                  }
                : null,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sm = widget.sessionManager;
    final sessions = sm.sessions;
    final activeId = sm.activeSessionId;

    if (sessions.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                AppIcons.monitorOff,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'No active sessions',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final activeIndex = sessions.indexWhere((s) => s.sessionId == activeId);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = MediaQuery.of(context).padding;
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

          return Stack(
            children: [
              Positioned.fill(
                child: IndexedStack(
                  index: activeIndex >= 0 ? activeIndex : 0,
                  children: sessions.map((s) => _buildRenderer(s)).toList(),
                ),
              ),

              Positioned(
                left: _pillX,
                top: _pillY,
                child: _buildDraggablePill(sessions, activeId, constraints),
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
            GestureDetector(
              onTap: _showSessionSwitcher,
              behavior: HitTestBehavior.opaque,
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
                    Icon(AppIcons.chevronUp, size: 14, color: cs.outline),
                  ],
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
    if (session.isScriptSession) {
      return ScriptRenderer(
        key: ValueKey('script_${session.sessionId}'),
        session: session,
        token: token,
        sessionManager: widget.sessionManager,
        terminalSettings: widget.terminalSettings,
        isVisible:
            widget.isVisible &&
            widget.sessionManager.activeSessionId == session.sessionId,
      );
    }
    switch (session.type) {
      case ConnectionType.guacamole:
        return GuacamoleRenderer(
          key: ValueKey('guac_${session.sessionId}'),
          session: session,
          token: token,
          sessionManager: widget.sessionManager,
        );
      case ConnectionType.terminal:
        return TerminalRenderer(
          key: ValueKey('term_${session.sessionId}'),
          session: session,
          token: token,
          sessionManager: widget.sessionManager,
          snippetManager: widget.snippetManager,
          aiManager: widget.aiManager,
          terminalSettings: widget.terminalSettings,
        );
      case ConnectionType.sftp:
        return SftpRenderer(
          key: ValueKey('sftp_${session.sessionId}'),
          session: session,
          token: token,
          sessionManager: widget.sessionManager,
          sftpSettings: widget.sftpSettings,
        );
    }
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

class _SessionSwitcherSheet extends StatelessWidget {
  final List<AppSession> sessions;
  final String? activeSessionId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final VoidCallback? onCloseAll;
  final bool isClosingAll;
  final VoidCallback? onExitFullscreen;

  const _SessionSwitcherSheet({
    required this.sessions,
    required this.activeSessionId,
    required this.onSelect,
    required this.onClose,
    this.onCloseAll,
    this.isClosingAll = false,
    this.onExitFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(AppIcons.layers, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Sessions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${sessions.length}',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: sessions.length,
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemBuilder: (_, i) {
                final s = sessions[i];
                return _SessionTile(
                  session: s,
                  isActive: s.sessionId == activeSessionId,
                  enabled: !isClosingAll,
                  onTap: () => onSelect(s.sessionId),
                  onClose: () => onClose(s.sessionId),
                );
              },
            ),
          ),
          if (onExitFullscreen != null) ...[
            const Divider(height: 1),
            ListTile(
              dense: true,
              enabled: !isClosingAll,
              leading: Icon(AppIcons.exitToApp, size: 20, color: cs.outline),
              title: Text(
                'Back to servers',
                style: TextStyle(fontSize: 14, color: cs.onSurface),
              ),
              onTap: onExitFullscreen,
              trailing: onCloseAll != null
                  ? (isClosingAll
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.error,
                            ),
                          )
                        : IconButton(
                            icon: Icon(
                              AppIcons.close,
                              size: 20,
                              color: cs.error,
                            ),
                            tooltip: 'Close all sessions',
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(8),
                            onPressed: onCloseAll,
                          ))
                  : null,
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final AppSession session;
  final bool isActive;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _SessionTile({
    required this.session,
    required this.isActive,
    this.enabled = true,
    required this.onTap,
    required this.onClose,
  });

  IconData get _icon {
    if (session.isScriptSession) return AppIcons.codeBracesBox;
    switch (session.type) {
      case ConnectionType.guacamole:
        return AppIcons.monitorSmall;
      case ConnectionType.terminal:
        return AppIcons.console;
      case ConnectionType.sftp:
        return AppIcons.folderOutline;
    }
  }

  String get _typeLabel {
    if (session.isScriptSession) return 'Script';
    switch (session.type) {
      case ConnectionType.guacamole:
        return 'Remote Desktop';
      case ConnectionType.terminal:
        return 'Terminal';
      case ConnectionType.sftp:
        return 'File Browser';
    }
  }

  String get _subtitle {
    if (!session.isScriptSession) {
      return '${session.server.name} · $_typeLabel';
    }
    final runtime = session.scriptRuntime;
    final status = switch (runtime?.status) {
      ScriptSessionStatus.connecting => 'Connecting',
      ScriptSessionStatus.running => 'Running',
      ScriptSessionStatus.waitingForInput => 'Waiting for input',
      ScriptSessionStatus.cancelling => 'Stopping',
      ScriptSessionStatus.cancelled => 'Stopped',
      ScriptSessionStatus.completed => 'Completed',
      ScriptSessionStatus.failed => 'Failed',
      ScriptSessionStatus.disconnected => 'Disconnected',
      null => 'Script',
    };
    final step =
        runtime != null &&
            runtime.stepCount > 0 &&
            runtime.currentStepNumber > 0
        ? ' · Step ${runtime.currentStepNumber} of ${runtime.stepCount}'
        : '';
    return '${session.server.name} · $status$step';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final needsInput = session.scriptNeedsInput;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: isActive ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.only(left: 14, right: 4),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (isActive ? cs.onPrimaryContainer : cs.primary)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _icon,
                size: 18,
                color: isActive ? cs.onPrimaryContainer : cs.primary,
              ),
            ),
            if (needsInput ||
                session.scriptRuntime?.status == ScriptSessionStatus.failed ||
                session.scriptRuntime?.status ==
                    ScriptSessionStatus.disconnected)
              Positioned(
                right: -3,
                top: -3,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: needsInput ? cs.tertiary : cs.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.surface, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          session.isScriptSession
              ? (session.scriptName ?? 'Script')
              : session.server.name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? cs.onPrimaryContainer : cs.onSurface,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: isActive
                ? cs.onPrimaryContainer.withValues(alpha: 0.7)
                : cs.outline,
          ),
        ),
        trailing: IconButton(
          icon: Icon(AppIcons.close, size: 16),
          onPressed: enabled ? onClose : null,
          color: isActive ? cs.onPrimaryContainer : cs.outline,
          tooltip: 'Close session',
        ),
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
