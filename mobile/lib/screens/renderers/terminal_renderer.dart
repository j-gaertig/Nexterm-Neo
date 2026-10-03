import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/app_icons.dart';
import 'package:web_socket_channel/io.dart';
import 'package:xterm/xterm.dart';

import '../../services/session_manager.dart';
import '../../services/connection_service.dart';
import '../../services/server_editor_service.dart';
import '../../models/managed_identity.dart';
import '../../utils/ai_manager.dart';
import '../../utils/snippet_manager.dart';
import '../../utils/password_prompt.dart';
import '../../utils/password_prompt_localizations.dart';
import '../../utils/terminal_key_input.dart';
import '../../utils/terminal_settings.dart';
import '../widgets/ai_assistant_sheet.dart';
import '../widgets/connection_loader.dart';
import 'password_fill_hint.dart';

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
  final GlobalKey<TerminalViewState> _terminalViewKey = GlobalKey<TerminalViewState>();
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

  @override
  void initState() {
    super.initState();
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
            !_sameIdentityIds(oldWidget.session.server.identities,
                widget.session.server.identities);
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

  static bool _sameIdentityIds(List<int>? a, List<int>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _onTerminalSettingsChanged() {
    // Mirrors web: disabling detection hides the hint and resets tracking.
    if (!widget.terminalSettings.passwordPromptDetection) {
      _promptLine = '';
      _hidePasswordHint();
    } else {
      // Reload so identities added while detection was off appear.
      unawaited(_loadPasswordIdentities());
    }
  }

  DateTime? _lastIdentityLoadAttempt;
  bool _identityLoadInFlight = false;
  bool _identityLoadQueued = false;

  /// Loads the server's password identities (web `IdentityContext` equivalent).
  /// Filters the global identity list down to identities attached to this
  /// server whose type carries a password, prioritizing the session identity
  /// exactly like the web client.
  ///
  /// Like the web context, identities load independently of the detection
  /// setting: the manual toolbar fill (web context-menu equivalent) stays
  /// available while detection is off and pastes without submitting.
  Future<void> _loadPasswordIdentities() async {
    // Coalesce overlapping requests: at most one load in flight, at most one
    // queued. A queued request whose snapshot was discarded by the guard
    // below is retried from `finally` instead of being dropped silently.
    if (_identityLoadInFlight) {
      _identityLoadQueued = true;
      return;
    }
    _identityLoadInFlight = true;
    _lastIdentityLoadAttempt = DateTime.now();
    // Snapshot request state: discard the result if the session or token
    // changed while the request was in flight.
    final requestToken = widget.token;
    final requestSessionId = widget.session.sessionId;
    final requestServerIds = <int>[
      ...?widget.session.server.identities,
    ];
    final requestIdentityId = widget.session.identityId;
    try {
      final all = await ServerEditorService.getIdentities(requestToken);
      if (!mounted) return;
      if (widget.session.sessionId != requestSessionId ||
          widget.token != requestToken) {
        _identityLoadQueued = true;
        return;
      }
      final serverIds = <int>[...requestServerIds];
      final sessionIdentityId = requestIdentityId;
      if (sessionIdentityId != null && !serverIds.contains(sessionIdentityId)) {
        serverIds.insert(0, sessionIdentityId);
      }
      final byId = <String, ManagedIdentity>{
        for (final identity in all) identity.id.toString(): identity,
      };
      final filtered = <PasswordIdentity>[];
      for (final id in serverIds) {
        final match = byId[id.toString()];
        if (match == null) continue;
        if (!passwordIdentityTypes.contains(match.authType)) continue;
        filtered.add(PasswordIdentity(id: match.id, username: match.username));
      }
      final hideHint = filtered.isEmpty && _passwordPromptVisible;
      // Prompt-race healing: the prompt may have arrived while identities
      // were still loading and the terminal may be idle since. Re-evaluate
      // once from the accumulated stream plus the live buffer.
      var showHint = false;
      if (filtered.isNotEmpty &&
          !_passwordPromptVisible &&
          widget.terminalSettings.passwordPromptDetection) {
        final term = widget.session.terminal;
        var candidate = _promptLine;
        if (term != null) {
          final bufferLine = readTerminalPromptLine(term);
          if (bufferLine.trim().isNotEmpty) candidate = bufferLine;
        }
        showHint = isPasswordPrompt(candidate);
      }
      setState(() {
        _passwordIdentities = filtered;
        if (hideHint) {
          _passwordPromptVisible = false;
          _passwordHintIndex = -1;
        } else if (showHint) {
          _passwordPromptVisible = true;
          _passwordHintIndex = 0;
        }
      });
    } catch (_) {
      // Best effort: without identities there is simply no hint. Backdate
      // the attempt so a failed load retries after ~15s, not 60s.
      _lastIdentityLoadAttempt =
          DateTime.now().subtract(const Duration(seconds: 45));
      if (!mounted) return;
      if (widget.session.sessionId != requestSessionId ||
          widget.token != requestToken) {
        _identityLoadQueued = true;
        return;
      }
      final hideHint = _passwordPromptVisible;
      setState(() {
        _passwordIdentities = [];
        if (hideHint) {
          _passwordPromptVisible = false;
          _passwordHintIndex = -1;
        }
      });
    } finally {
      _identityLoadInFlight = false;
      if (_identityLoadQueued && mounted) {
        _identityLoadQueued = false;
        unawaited(_loadPasswordIdentities());
      }
    }
  }

  void _trackPasswordPrompt(String data) {
    // Always accumulate: the prompt may arrive while identities are still
    // loading (or detection is off); evaluation below decides visibility.
    // Bounded to the last 256 code points by `updatePromptLine`.
    _promptLine = updatePromptLine(_promptLine, data);
    if (_passwordIdentities.isEmpty) {
      // An identity may have been added while this terminal was open (the
      // web client reloads live via IdentityContext). Retry at most once a
      // minute instead of polling on every chunk. This runs independently of
      // the detection setting so the manual toolbar fill heals as well.
      final last = _lastIdentityLoadAttempt;
      if (last == null ||
          DateTime.now().difference(last) > const Duration(seconds: 60)) {
        unawaited(_loadPasswordIdentities());
      }
      return;
    }
    if (!widget.terminalSettings.passwordPromptDetection) return;
    var candidate = _promptLine;
    final bufferLine = readTerminalPromptLine(_terminal);
    if (bufferLine.trim().isNotEmpty) candidate = bufferLine;
    if (isPasswordPrompt(candidate)) {
      if (!_passwordPromptVisible && mounted) {
        setState(() {
          _passwordPromptVisible = true;
          _passwordHintIndex = 0;
        });
      }
    } else {
      _hidePasswordHint();
    }
  }

  void _hidePasswordHint() {
    if (!_passwordPromptVisible) return;
    if (mounted) {
      setState(() {
        _passwordPromptVisible = false;
        _passwordHintIndex = -1;
      });
    } else {
      _passwordPromptVisible = false;
      _passwordHintIndex = -1;
    }
  }

  void _cyclePasswordHint([int offset = 1]) {
    if (_passwordIdentities.length < 2 || !mounted) return;
    setState(() {
      final count = _passwordIdentities.length;
      _passwordHintIndex = (_passwordHintIndex + offset) % count;
    });
  }

  /// Fills the identity password via `POST /paste-password` (web
  /// `fillIdentityPassword`). [identityId] null pastes the session default;
  /// `submit` is true while a prompt is visible, exactly like the web client.
  Future<void> _fillIdentityPassword([dynamic identityId]) async {
    final shouldSubmit = _passwordPromptVisible;
    _hidePasswordHint();
    try {
      await ConnectionService.pasteIdentityPassword(
        token: widget.token,
        sessionId: widget.session.sessionId,
        identityId: identityId == null
            ? null
            : (identityId is int
                ? identityId
                : int.tryParse(identityId.toString())),
        submit: shouldSubmit,
      );
    } catch (_) {
      // A failed fill likely means the identity changed server-side; reload
      // so the next prompt shows the current list (web heals via live push).
      unawaited(_loadPasswordIdentities());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to paste password'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (mounted) _terminalFocusNode.requestFocus();
  }

  void _onTerminalChanged() => _cursorRevision.value++;

  void _onFocusChanged() {
    if (!_terminalFocusNode.hasFocus) _stopAllArrowRepeats();
    if (mounted) setState(() => _showKeyboardToolbar = _terminalFocusNode.hasFocus);
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (!mounted ||
        !_terminalFocusNode.hasFocus ||
        event is! KeyDownEvent) {
      return false;
    }

    // Inactive tabs stay alive in the IndexedStack: never consume keys for a
    // session that is not currently visible.
    if (widget.sessionManager.activeSessionId != null &&
        widget.sessionManager.activeSessionId != widget.session.sessionId) {
      return false;
    }

    // Mirrors web `attachCustomKeyEventHandler` while the password hint is
    // visible: Tab/Enter fills, Escape dismisses, Up/Down cycles identities.
    if (_passwordPromptVisible) {
      final logicalKey = event.logicalKey;
      final isTab = logicalKey == LogicalKeyboardKey.tab;
      final isEnter = logicalKey == LogicalKeyboardKey.enter ||
          logicalKey == LogicalKeyboardKey.numpadEnter;
      final isEscape = logicalKey == LogicalKeyboardKey.escape;
      final isUp = logicalKey == LogicalKeyboardKey.arrowUp;
      final isDown = logicalKey == LogicalKeyboardKey.arrowDown;
      if (isTab || isEnter) {
        final count = _passwordIdentities.length;
        final current = count > 0
            ? _passwordIdentities[_passwordHintIndex < 0
                ? 0
                : (_passwordHintIndex >= count
                    ? count - 1
                    : _passwordHintIndex)]
            : null;
        unawaited(_fillIdentityPassword(current?.id));
        return true;
      }
      if (isEscape) {
        _hidePasswordHint();
        return true;
      }
      if ((isUp || isDown) && _passwordIdentities.length > 1) {
        _cyclePasswordHint(isUp ? -1 : 1);
        return true;
      }
    }

    if (!_ctrlPressed && !_altPressed) {
      return false;
    }

    final key = _hardwareKeyName(event);
    if (key == null) return false;
    _sendTerminalKey(key);
    return true;
  }

  String? _hardwareKeyName(KeyDownEvent event) {
    final character = event.character;
    if (character != null && character.isNotEmpty) return character;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) return 'ESC';
    if (key == LogicalKeyboardKey.tab) return 'TAB';
    if (key == LogicalKeyboardKey.arrowUp) return 'UP';
    if (key == LogicalKeyboardKey.arrowDown) return 'DOWN';
    if (key == LogicalKeyboardKey.arrowLeft) return 'LEFT';
    if (key == LogicalKeyboardKey.arrowRight) return 'RIGHT';
    if (key == LogicalKeyboardKey.home) return 'HOME';
    if (key == LogicalKeyboardKey.end) return 'END';
    if (key == LogicalKeyboardKey.pageUp) return 'PGUP';
    if (key == LogicalKeyboardKey.pageDown) return 'PGDN';
    if (key == LogicalKeyboardKey.f1) return 'F1';
    if (key == LogicalKeyboardKey.f2) return 'F2';
    if (key == LogicalKeyboardKey.f3) return 'F3';
    if (key == LogicalKeyboardKey.f4) return 'F4';
    if (key == LogicalKeyboardKey.f5) return 'F5';
    if (key == LogicalKeyboardKey.f6) return 'F6';
    if (key == LogicalKeyboardKey.f7) return 'F7';
    if (key == LogicalKeyboardKey.f8) return 'F8';
    if (key == LogicalKeyboardKey.f9) return 'F9';
    if (key == LogicalKeyboardKey.f10) return 'F10';
    if (key == LogicalKeyboardKey.f11) return 'F11';
    if (key == LogicalKeyboardKey.f12) return 'F12';
    return null;
  }

  void _startArrowHold(String key) {
    _stopArrowRepeat(key);
    _sendSpecialKey(key);
    _arrowRepeatTimers[key] = Timer(_arrowRepeatDelay, () => _repeatArrow(key));
  }

  void _repeatArrow(String key) {
    if (!mounted || !_connected || !_terminalFocusNode.hasFocus) {
      _stopArrowRepeat(key);
      return;
    }

    _sendSpecialKey(key);
    _arrowRepeatTimers[key] = Timer(_arrowRepeatInterval, () => _repeatArrow(key));
  }

  void _stopArrowRepeat(String key) {
    _arrowRepeatTimers.remove(key)?.cancel();
  }

  void _stopAllArrowRepeats() {
    for (final timer in _arrowRepeatTimers.values) {
      timer.cancel();
    }
    _arrowRepeatTimers.clear();
  }

  void _setupTerminal() {
    if (_initialized) return;
    _initialized = true;

    _terminal.onOutput = (data) {
      if (!mounted || _channel == null) return;
      // Mirrors web `term.onData`: any user input dismisses the hint.
      // Note the deliberate mobile asymmetry: a soft-keyboard Enter arrives
      // here as plain input (it dismisses without filling), while a hardware
      // Tab/Enter is intercepted above and fills. Tapping the hint card is
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
            // TOTP second-factor prompts (\x02) are written without the
            // marker and never feed password detection, like the web client.
            final isTotpPrompt = data.startsWith('\x02');
            final text =
                isTotpPrompt ? data.substring(1) : data;
            _terminal.write(text);
            if (!isTotpPrompt) _trackPasswordPrompt(text);
          }
        },
        onError: (error) {
          _stopAllArrowRepeats();
          if (mounted) setState(() { _errorMessage = 'Connection error: $error'; _connected = false; });
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
        _channel?.sink.add(_terminal.viewHeight > 0 && _terminal.viewWidth > 0
            ? '\x01${_terminal.viewWidth},${_terminal.viewHeight}'
            : '\x0180,30');
      });
    } else {
      _connected = widget.session.isConnected;
    }
  }

  @override
  void dispose() {
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

  void _sendSpecialKey(String key) {
    switch (key) {
      case 'CTRL': if (mounted) setState(() => _ctrlPressed = !_ctrlPressed); return;
      case 'ALT': if (mounted) setState(() => _altPressed = !_altPressed); return;
      default: _sendTerminalKey(key); return;
    }
  }

  void _sendFunctionKey(int n) {
    _sendTerminalKey('F$n');
  }

  void _sendTerminalText(String text) {
    // Mirrors web `term.onData`: any user input dismisses the hint first, so
    // a later fill cannot submit into a stale prompt.
    _hidePasswordHint();
    final ctrl = _ctrlPressed;
    final alt = _altPressed;
    _channel?.sink.add(TerminalKeyInput.applyText(text, ctrl: ctrl, alt: alt));
    _clearModifiers();
  }

  void _sendTerminalKey(String key, {bool forceCtrl = false}) {
    // Same as above: toolbar and hardware-key input dismiss the hint.
    _hidePasswordHint();
    final ctrl = forceCtrl || _ctrlPressed;
    final alt = _altPressed;
    final data = TerminalKeyInput.applyKey(key, ctrl: ctrl, alt: alt);
    if (data.isEmpty) return;
    _channel?.sink.add(data);
    _clearModifiers();
  }

  void _clearModifiers() {
    if (_ctrlPressed || _altPressed) {
      if (mounted) {
        setState(() {
          _ctrlPressed = false;
          _altPressed = false;
        });
      } else {
        _ctrlPressed = false;
        _altPressed = false;
      }
    }
  }

  void _showAISheet() {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => AIAssistantSheet(
        token: widget.token,
        sessionId: widget.session.sessionId,
        serverName: widget.session.server.name,
      ),
    );
  }

  void _showSnippets() {
    if (!mounted) return;
    final sm = widget.snippetManager;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
        builder: (ctx, scrollController) {
          if (sm.isLoading) return const Center(child: CircularProgressIndicator());
          if (sm.error != null) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(AppIcons.alertCircleOutline, size: 48, color: Theme.of(ctx).colorScheme.error),
                const SizedBox(height: 16),
                Text('Failed to load snippets', style: Theme.of(ctx).textTheme.titleMedium),
              ]),
            ));
          }
          if (sm.snippets.isEmpty) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(AppIcons.codeBracesBox, size: 48, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text('No snippets available', style: Theme.of(ctx).textTheme.titleMedium),
              ]),
            ));
          }
          return Column(children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                border: Border(bottom: BorderSide(color: Theme.of(ctx).colorScheme.outlineVariant)),
              ),
              child: Row(children: [
                Icon(AppIcons.codeBraces, color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 12),
                Text('Snippets', style: Theme.of(ctx).textTheme.titleLarge),
                const Spacer(),
                IconButton(icon: Icon(AppIcons.close), onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
            Expanded(child: ListView.builder(
              controller: scrollController,
              itemCount: sm.snippets.length,
              itemBuilder: (ctx, i) {
                final s = sm.snippets[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(ctx).colorScheme.primaryContainer,
                    child: Icon(AppIcons.console, color: Theme.of(ctx).colorScheme.onPrimaryContainer, size: 20),
                  ),
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: s.description != null ? Text(s.description!, maxLines: 2, overflow: TextOverflow.ellipsis) : null,
                  trailing: Icon(AppIcons.chevronRight, size: 16),
                  onTap: () { Navigator.pop(ctx); _channel?.sink.add(s.command); },
                );
              },
            )),
          ]);
        },
      ),
    );
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
                          // (which hides the hint): this card is
                          // bottom-anchored and never misplaced by scrolling,
                          // and hiding on every autoscroll from incoming
                          // output would make the hint flicker.
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
                              theme: _hideTerminalCursor(widget.terminalSettings.colorTheme.theme),
                              cursorType: TerminalCursorType.block,
                              keyboardType: TextInputType.visiblePassword,
                              textStyle: TerminalStyle(
                                fontSize: widget.terminalSettings.fontSize,
                                fontFamily: GoogleFonts.jetBrainsMono().fontFamily ?? 'monospace',
                                height: 1.2,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                                    color: widget.terminalSettings.colorTheme.theme.cursor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_passwordPromptVisible &&
                      _passwordIdentities.isNotEmpty &&
                      widget.terminalSettings.passwordPromptDetection)
                    SafeArea(
                      top: false,
                      // The keyboard toolbar below already applies the bottom
                      // inset when visible; avoid padding twice.
                      bottom: !_showKeyboardToolbar,
                      child: PasswordFillHint(
                        items: _passwordIdentities,
                        selectedIndex: _passwordHintIndex,
                        onFill: (id) => _fillIdentityPassword(id),
                        onCycle: () => _cyclePasswordHint(1),
                        onDismiss: _hidePasswordHint,
                      ),
                    ),
                  if (_showKeyboardToolbar) _buildKeyboardToolbar(),
                ],
              ),
            ),
            Positioned.fill(
              child: ConnectionLoader(visible: !_receivedData && _errorMessage == null),
            ),
          ],
        );
      },
    );
  }

  Widget _errorBanner() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(8), color: colors.errorContainer,
      child: Row(children: [
        Icon(AppIcons.alertCircleOutline, color: colors.onErrorContainer),
        const SizedBox(width: 8),
        Expanded(child: Text(_errorMessage!, style: TextStyle(color: colors.onErrorContainer))),
        IconButton(icon: Icon(AppIcons.close), onPressed: () => setState(() => _errorMessage = null), color: colors.onErrorContainer),
      ]),
    );
  }

  Widget _buildKeyboardToolbar() {
    final ts = widget.terminalSettings;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _toolbarBtn('ESC'), const SizedBox(width: 8),
              _toolbarBtn('TAB'), const SizedBox(width: 8),
              // Manual fill (web context-menu / `paste-identity-password`
              // keybind equivalent): pastes the session default password
              // without submitting unless a prompt is currently visible.
              if (_passwordIdentities.isNotEmpty) ...[
                Tooltip(
                  message: PasswordPromptLocalizations.of(context)
                      .pasteIdentityPassword,
                  child: _toolbarBtn(
                    'Password',
                    icon: AppIcons.key,
                    onPressed: () => _fillIdentityPassword(),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              for (final group in ts.groupOrder)
                if (ts.isGroupEnabled(group)) ..._buildGroupButtons(group),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGroupButtons(ToolbarGroup group) {
    switch (group) {
      case ToolbarGroup.modifiers:
        return [
          _toolbarBtn('CTRL', isToggle: true, isActive: _ctrlPressed), const SizedBox(width: 8),
          _toolbarBtn('ALT', isToggle: true, isActive: _altPressed), const SizedBox(width: 16),
        ];
      case ToolbarGroup.signals:
        return [
          _toolbarBtn('^C', onPressed: () => _sendTerminalKey('c', forceCtrl: true), compact: true), const SizedBox(width: 8),
          _toolbarBtn('^Z', onPressed: () => _sendTerminalKey('z', forceCtrl: true), compact: true), const SizedBox(width: 8),
          _toolbarBtn('^D', onPressed: () => _sendTerminalKey('d', forceCtrl: true), compact: true), const SizedBox(width: 16),
        ];
      case ToolbarGroup.arrows:
        return [
          _toolbarBtn('UP', icon: AppIcons.arrowUp, holdKey: 'UP', compact: true), const SizedBox(width: 8),
          _toolbarBtn('DOWN', icon: AppIcons.arrowDown, holdKey: 'DOWN', compact: true), const SizedBox(width: 8),
          _toolbarBtn('LEFT', icon: AppIcons.arrowLeft, holdKey: 'LEFT', compact: true), const SizedBox(width: 8),
          _toolbarBtn('RIGHT', icon: AppIcons.arrowRight, holdKey: 'RIGHT', compact: true), const SizedBox(width: 16),
        ];
      case ToolbarGroup.navigation:
        return [
          _toolbarBtn('HOME', compact: true), const SizedBox(width: 8),
          _toolbarBtn('END', compact: true), const SizedBox(width: 8),
          _toolbarBtn('PGUP', compact: true), const SizedBox(width: 8),
          _toolbarBtn('PGDN', compact: true), const SizedBox(width: 16),
        ];
      case ToolbarGroup.functionKeys:
        return [
          for (int i = 1; i <= 12; i++) ...[
            _toolbarBtn('F$i', onPressed: () => _sendFunctionKey(i), compact: true),
            if (i < 12) const SizedBox(width: 8),
          ],
        ];
    }
  }

  Widget _toolbarBtn(String label, {IconData? icon, VoidCallback? onPressed, String? holdKey, bool isToggle = false, bool isActive = false, bool compact = false}) {
    final theme = Theme.of(context);
    final bgColor = isActive ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
    final fgColor = isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    return Material(
      color: bgColor, borderRadius: BorderRadius.circular(12), elevation: isActive ? 2 : 0,
      child: InkWell(
        onTap: holdKey == null ? onPressed ?? () => _sendSpecialKey(label) : () {},
        onTapDown: holdKey == null ? null : (_) => _startArrowHold(holdKey),
        onTapUp: holdKey == null ? null : (_) => _stopArrowRepeat(holdKey),
        onTapCancel: holdKey == null ? null : () => _stopArrowRepeat(holdKey),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: BoxConstraints(minWidth: compact ? 44 : 56, minHeight: 44),
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: 10),
          child: Center(
            child: icon != null
                ? Icon(icon, size: 18, color: fgColor, semanticLabel: label)
                : Text(label, style: TextStyle(fontSize: compact ? 13 : 14, fontWeight: FontWeight.w600, color: fgColor)),
          ),
        ),
      ),
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
        !stackRenderObject.hasSize) return;

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
