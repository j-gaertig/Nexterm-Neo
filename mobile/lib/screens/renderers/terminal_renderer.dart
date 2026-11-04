import '../../utils/api_exception.dart';
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kterm/kterm.dart';
import 'package:web_socket_channel/io.dart';

import '../../models/managed_identity.dart';
import '../../services/connection_service.dart';
import '../../services/server_editor_service.dart';
import '../../services/session_manager.dart';
import '../../utils/ai_manager.dart';
import '../../utils/app_icons.dart';
import '../../utils/password_prompt.dart';
import '../../utils/snippet_manager.dart';
import '../../utils/terminal_font.dart';
import '../../utils/terminal_graphics.dart';
import '../../utils/terminal_image_fetch.dart';
import '../../utils/terminal_key_input.dart';
import '../../utils/terminal_settings.dart';
import '../widgets/ai_assistant_sheet.dart';
import '../widgets/connection_loader.dart';
import 'password_fill_hint.dart';

part 'terminal/password.dart';
part 'terminal/input.dart';
part 'terminal/ui.dart';

class TerminalRenderer extends StatefulWidget {
  final AppSession session;
  final String token;
  final SessionManager sessionManager;
  final SnippetManager snippetManager;
  final TerminalSettings terminalSettings;
  final AIManager aiManager;
  final VoidCallback? onDisconnected;

  const TerminalRenderer({
    super.key,
    required this.session,
    required this.token,
    required this.sessionManager,
    required this.snippetManager,
    required this.terminalSettings,
    required this.aiManager,
    this.onDisconnected,
  });

  @override
  State<TerminalRenderer> createState() => _TerminalRendererState();
}

class _TerminalRendererState extends State<TerminalRenderer> {
  Terminal get _terminal => widget.session.terminal!;
  IOWebSocketChannel? get _channel => widget.session.termChannel;
  final GlobalKey<TerminalViewState> _terminalViewKey =
      GlobalKey<TerminalViewState>();
  final GlobalKey _cursorOverlayStackKey = GlobalKey();
  final ValueNotifier<int> _cursorRevision = ValueNotifier(0);
  bool _connected = false;
  bool _receivedData = false;
  String? _errorMessage;
  final FocusNode _terminalFocusNode = FocusNode();
  bool _showKeyboardToolbar = false;
  bool _ctrlPressed = false;
  bool _altPressed = false;
  bool _initialized = false;
  late TerminalGraphicsProcessor _graphics;
  final Map<String, Timer> _arrowRepeatTimers = {};
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _arrowRepeatDelay = Duration(milliseconds: 400);
  static const Duration _arrowRepeatInterval = Duration(milliseconds: 80);

  // Password prompt detection (mirrors web `XtermRenderer.jsx`).
  String _promptLine = '';
  List<PasswordIdentity> _passwordIdentities = [];
  int _passwordHintIndex = -1;
  bool _passwordPromptVisible = false;
  bool _passwordFillInFlight = false;

  TerminalGraphicsProcessor _createGraphicsProcessor() {
    return TerminalGraphicsProcessor(
      fetchImage: (path) => fetchRemoteTerminalImage(
        token: widget.token,
        sessionId: widget.session.sessionId,
        path: path,
      ),
      viewportMetrics: () => (
        columns: _terminal.viewWidth,
        rows: _terminal.viewHeight,
        cellWidth: _terminal.cellPixelWidth,
        cellHeight: _terminal.cellPixelHeight,
      ),
      onOutput: _writeProcessedOutput,
      onError: (error) => debugPrint('Terminal graphics: $error'),
    );
  }

  void _writeProcessedOutput(String text) {
    if (!mounted || text.isEmpty) return;
    // TOTP second-factor prompts (\x02) are written without the marker and
    // never feed password detection, like the web client.
    if (text.startsWith('\x02')) {
      _terminal.write(text.substring(1));
      return;
    }
    _terminal.write(text);
    _trackPasswordPrompt(text);
  }

  void _resetGraphicsProcessor() {
    _graphics.dispose();
    _graphics = _createGraphicsProcessor();
  }

  @override
  void initState() {
    super.initState();
    _graphics = _createGraphicsProcessor();
    _terminal.addListener(_onTerminalChanged);
    _terminalFocusNode.addListener(_onFocusChanged);
    widget.terminalSettings.addListener(_onTerminalSettingsChanged);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    widget.session.showSnippets = _showSnippets;
    widget.session.showAI = _showAISheet;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.session.onCallbacksReady?.call();
    });
    _loadPasswordIdentities();
    _setupTerminal();
  }

  @override
  void didUpdateWidget(covariant TerminalRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Note: renderers are keyed by sessionId (`term_<id>`), so a different
    // sessionId remounts instead of updating. This branch therefore handles
    // token refreshes and server-data refreshes (e.g. identities edited
    // while the terminal is open) for the same session.
    final sessionChanged =
        oldWidget.session.sessionId != widget.session.sessionId;
    final tokenChanged = oldWidget.token != widget.token;
    final identitiesChanged =
        oldWidget.session.identityId != widget.session.identityId ||
        !_TerminalPassword._sameIdentityIds(
          oldWidget.session.server.identities,
          widget.session.server.identities,
        );
    if (sessionChanged || tokenChanged || identitiesChanged) {
      _passwordPromptVisible = false;
      _passwordHintIndex = -1;
      _promptLine = '';
      _passwordIdentities = [];
      unawaited(_loadPasswordIdentities());
    }
    if (oldWidget.terminalSettings != widget.terminalSettings) {
      oldWidget.terminalSettings.removeListener(_onTerminalSettingsChanged);
      widget.terminalSettings.addListener(_onTerminalSettingsChanged);
    }
  }

  DateTime? _lastIdentityLoadAttempt;
  bool _identityLoadInFlight = false;
  bool _identityLoadQueued = false;

  void _onFocusChanged() {
    if (!_terminalFocusNode.hasFocus) _stopAllArrowRepeats();
    if (mounted) {
      setState(() => _showKeyboardToolbar = _terminalFocusNode.hasFocus);
    }
  }

  void _setupTerminal() {
    if (_initialized) return;
    _initialized = true;

    _terminal.onOutput = (data) {
      if (!mounted || _channel == null) return;
      // Mirrors web `term.onData`: any user input dismisses the hint.
      // Note the deliberate mobile asymmetry: a soft-keyboard Enter arrives
      // here as plain input (it dismisses without filling), while a hardware
      // Tab/Enter is intercepted above and fills. Tapping the key button is
      // the primary touch flow.
      _hidePasswordHint();
      _sendTerminalText(data);
    };

    _terminal.onResize = (w, h, _, __) {
      if (mounted && _connected && _channel != null) {
        _channel?.sink.add('\x01$w,$h');
      }
    };

    if (widget.session.termSubscription == null) {
      widget.session.termSubscription = _channel?.stream.listen(
        (data) {
          if (!_receivedData && mounted) {
            setState(() => _receivedData = true);
          }
          if (data is String) {
            // The processor writes through onOutput before the next chunk is
            // processed, so a slow image fetch cannot reorder terminal writes.
            unawaited(
              _graphics.push(data).catchError((Object error) {
                debugPrint('Terminal graphics processing failed: $error');
                return '';
              }),
            );
          }
        },
        onError: (error) {
          _stopAllArrowRepeats();
          if (mounted) {
            setState(() {
              _errorMessage = friendlyApiError(
                error,
                fallback: 'Connection lost. Reconnecting...',
              );
              _connected = false;
            });
          }
          widget.session.isConnected = false;
          unawaited(_attemptReconnect());
        },
        onDone: () {
          _stopAllArrowRepeats();
          if (mounted) setState(() => _connected = false);
          widget.session.isConnected = false;
          unawaited(_attemptReconnect());
        },
      );

      if (mounted) setState(() => _connected = true);
      widget.session.isConnected = true;
      _reconnectAttempts = 0;

      Future.delayed(const Duration(milliseconds: 100), () {
        if (_channel == null) return;
        _channel?.sink.add(
          _terminal.viewHeight > 0 && _terminal.viewWidth > 0
              ? '\x01${_terminal.viewWidth},${_terminal.viewHeight}'
              : '\x0180,30',
        );
      });
    } else {
      _connected = widget.session.isConnected;
    }
  }

  @override
  void dispose() {
    _graphics.dispose();
    _terminal.removeListener(_onTerminalChanged);
    widget.terminalSettings.removeListener(_onTerminalSettingsChanged);
    _cursorRevision.dispose();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _stopAllArrowRepeats();
    _terminalFocusNode.removeListener(_onFocusChanged);
    _terminalFocusNode.dispose();
    super.dispose();
  }

  /// Reconnects a dropped terminal session with up to 5 attempts and 1-5s
  /// backoff. On success the stream state is reset (fresh size handshake,
  /// cleared prompt tracking) and the identity list is refreshed.
  Future<void> _attemptReconnect() async {
    if (!mounted || _reconnectAttempts >= _maxReconnectAttempts) {
      widget.onDisconnected?.call();
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts.clamp(1, 5));
    await Future.delayed(delay);

    if (!mounted) return;

    final success = await widget.sessionManager.reconnectTerminalSession(
      token: widget.token,
      session: widget.session,
    );

    if (!mounted) return;

    if (success) {
      _initialized = false;
      _resetGraphicsProcessor();
      widget.session.termSubscription = null;
      // Fresh stream: drop prompt tracking so a stale hint cannot submit
      // into the new shell, then refresh the identity list.
      _promptLine = '';
      _hidePasswordHint();
      unawaited(_loadPasswordIdentities());
      setState(() {
        _errorMessage = null;
        _receivedData = false;
      });
      _setupTerminal();
    } else {
      unawaited(_attemptReconnect());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.terminalSettings,
      builder: (context, child) {
        return Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  if (_errorMessage != null) _errorBanner(),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _terminalFocusNode.requestFocus(),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (_) {
                          // Deliberate divergence from web `term.onScroll`
                          // (which hides the hint): this button is
                          // bottom-anchored and never misplaced by scrolling,
                          // and hiding on every autoscroll from incoming
                          // output would make it flicker.
                          _cursorRevision.value++;
                          return false;
                        },
                        child: Stack(
                          key: _cursorOverlayStackKey,
                          fit: StackFit.expand,
                          children: [
                            TerminalView(
                              _terminal,
                              key: _terminalViewKey,
                              theme: _hideTerminalCursor(
                                widget.terminalSettings.colorTheme.theme,
                              ),
                              cursorType: TerminalCursorType.block,
                              keyboardType: TextInputType.visiblePassword,
                              textStyle: TerminalStyle(
                                fontSize: widget.terminalSettings.fontSize,
                                fontFamily: terminalNerdFontFamily,
                                fontFamilyFallback: terminalNerdFontFallback,
                                height: 1.2,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              focusNode: _terminalFocusNode,
                              autofocus: false,
                              deleteDetection: Platform.isIOS,
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _LineCursorPainter(
                                    terminal: _terminal,
                                    terminalViewKey: _terminalViewKey,
                                    stackKey: _cursorOverlayStackKey,
                                    repaint: _cursorRevision,
                                    color: widget
                                        .terminalSettings
                                        .colorTheme
                                        .theme
                                        .cursor,
                                  ),
                                ),
                              ),
                            ),
                            // Compact key button floats at the bottom-right of
                            // the terminal, directly above the keyboard
                            // toolbar, and only while a password prompt is
                            // detected. It takes no layout space away from the
                            // terminal.
                            _buildPasswordHintOverlay(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_showKeyboardToolbar) _buildKeyboardToolbar(),
                ],
              ),
            ),
            Positioned.fill(
              child: ConnectionLoader(
                visible: !_receivedData && _errorMessage == null,
              ),
            ),
          ],
        );
      },
    );
  }
}

TerminalTheme _hideTerminalCursor(TerminalTheme theme) => TerminalTheme(
  cursor: Colors.transparent,
  selection: theme.selection,
  foreground: theme.foreground,
  background: theme.background,
  black: theme.black,
  white: theme.white,
  red: theme.red,
  green: theme.green,
  yellow: theme.yellow,
  blue: theme.blue,
  magenta: theme.magenta,
  cyan: theme.cyan,
  brightBlack: theme.brightBlack,
  brightRed: theme.brightRed,
  brightGreen: theme.brightGreen,
  brightYellow: theme.brightYellow,
  brightBlue: theme.brightBlue,
  brightMagenta: theme.brightMagenta,
  brightCyan: theme.brightCyan,
  brightWhite: theme.brightWhite,
  searchHitBackground: theme.searchHitBackground,
  searchHitBackgroundCurrent: theme.searchHitBackgroundCurrent,
  searchHitForeground: theme.searchHitForeground,
);

class _LineCursorPainter extends CustomPainter {
  _LineCursorPainter({
    required this.terminal,
    required this.terminalViewKey,
    required this.stackKey,
    required this.repaint,
    required this.color,
  }) : super(repaint: repaint);

  final Terminal terminal;
  final GlobalKey<TerminalViewState> terminalViewKey;
  final GlobalKey stackKey;
  final Listenable repaint;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!terminal.cursorVisibleMode) return;

    final cursorRect = terminalViewKey.currentState?.globalCursorRect;
    final stackRenderObject = stackKey.currentContext?.findRenderObject();
    if (cursorRect == null ||
        stackRenderObject is! RenderBox ||
        !stackRenderObject.hasSize) {
      return;
    }

    final cursorOffset = stackRenderObject.globalToLocal(cursorRect.topLeft);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    canvas.drawLine(
      cursorOffset,
      cursorOffset.translate(0, cursorRect.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_LineCursorPainter oldDelegate) =>
      oldDelegate.terminal != terminal ||
      oldDelegate.terminalViewKey != terminalViewKey ||
      oldDelegate.stackKey != stackKey ||
      oldDelegate.repaint != repaint ||
      oldDelegate.color != color;
}
