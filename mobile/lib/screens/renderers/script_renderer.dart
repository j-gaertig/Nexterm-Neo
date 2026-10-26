import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:kterm/kterm.dart';

import '../../services/script_connection.dart';
import '../../services/session_manager.dart';
import '../../utils/api_exception.dart';
import '../../utils/script_protocol.dart';
import '../../utils/terminal_font.dart';
import '../../utils/terminal_graphics.dart';
import '../../utils/terminal_image_fetch.dart';
import '../../utils/terminal_settings.dart';
import 'script_execution_controller.dart';
import '../widgets/script/script_execution_dock.dart';
import '../widgets/script/script_message_sheet.dart';
import '../widgets/script/script_prompt_sheet.dart';
import '../widgets/script/script_sheet_result.dart';
import '../widgets/script/script_sheet_shell.dart';
import '../widgets/script/script_summary_sheet.dart';
import '../widgets/script/script_table_sheet.dart';

/// Renders a script execution session on `/ws/term`. Raw terminal output
/// streams into a read-only terminal using the user's terminal theme and font
/// settings; `\x1F` control messages drive the execution dock and modal
/// prompts. Reconnects are always manual, matching the web `ReconnectPolicy`.
class ScriptRenderer extends StatefulWidget {
  final AppSession session;
  final String token;
  final SessionManager sessionManager;
  final TerminalSettings terminalSettings;

  /// True only while this session is both the active session and the sessions
  /// tab is visible. Prompts for background scripts stay queued and are
  /// surfaced through the navigation attention banner instead of opening a
  /// modal over another tab.
  final bool isVisible;

  const ScriptRenderer({
    super.key,
    required this.session,
    required this.token,
    required this.sessionManager,
    required this.terminalSettings,
    required this.isVisible,
  });

  @override
  State<ScriptRenderer> createState() => _ScriptRendererState();
}

class _ScriptRendererState extends State<ScriptRenderer> {
  Terminal get _terminal => widget.session.terminal!;

  late final ScriptStreamParser _parser;
  late final TerminalGraphicsProcessor _graphics;
  late final ScriptExecutionController _controller;

  ScriptConnection? _connection;
  ScriptConnection? _failedConnection;
  bool _connected = false;
  bool _closing = false;
  bool _sheetShowing = false;
  VoidCallback? _popActiveSheet;
  ScriptSheetRequest? _activeSheetRequest;
  int _sheetGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller = ScriptExecutionController(
      scriptName: widget.session.scriptName ?? 'Script',
    );
    _controller.addListener(_syncRuntimeState);
    _syncRuntimeState();

    _graphics = TerminalGraphicsProcessor(
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
      onError: (error) => debugPrint('Script terminal graphics: $error'),
    );
    _parser = ScriptStreamParser(
      onTerminalData: (data) {
        _graphics
            .push(data)
            .then((output) {
              if (mounted && output.isNotEmpty) _terminal.write(output);
            })
            .catchError((Object error) {
              debugPrint('Script terminal graphics processing failed: $error');
            });
      },
      onEvent: _handleEvent,
    );
    _terminal.onResize = (width, height, _, __) {
      if (mounted && _connected) {
        _connection?.send('\x01$width,$height');
      }
    };
    widget.terminalSettings.addListener(_onSettingsChanged);
    _attachConnection();
  }

  @override
  void didUpdateWidget(covariant ScriptRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.isVisible) {
          _presentNextSheetIfAllowed();
        } else {
          _dismissActiveSheet();
        }
      });
    }
    if (oldWidget.terminalSettings != widget.terminalSettings) {
      oldWidget.terminalSettings.removeListener(_onSettingsChanged);
      widget.terminalSettings.addListener(_onSettingsChanged);
    }
  }

  @override
  void dispose() {
    widget.terminalSettings.removeListener(_onSettingsChanged);
    _controller.removeListener(_syncRuntimeState);
    _controller.dispose();
    _graphics.dispose();
    _parser.discardPending();
    _terminal.onResize = null;
    widget.session.termSubscription?.cancel();

    _sheetGeneration++;
    final pop = _popActiveSheet;
    _popActiveSheet = null;
    _activeSheetRequest = null;
    _sheetShowing = false;
    if (pop != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => pop());
    }
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _syncRuntimeState() {
    widget.sessionManager.updateScriptRuntime(
      widget.session.sessionId,
      _controller.toRuntimeState(),
    );
  }

  // --- WebSocket lifecycle -------------------------------------------------

  Future<void> _attachConnection() async {
    _parser.discardPending();
    final connection = widget.session.scriptConnection;
    if (connection == null) {
      _controller.markDisconnected(
        message: 'No script connection is available.',
      );
      _dismissActiveSheet();
      return;
    }

    await widget.session.termSubscription?.cancel();
    widget.session.termSubscription = null;

    if (!mounted || !identical(widget.session.scriptConnection, connection)) {
      return;
    }

    _connection = connection;
    _failedConnection = null;
    _connected = false;

    final subscription = connection.stream.listen(
      (data) {
        if (!mounted || !identical(_connection, connection)) return;
        if (data is String) {
          _parser.processChunk(data);
        } else if (data is List<int>) {
          _parser.processChunk(utf8.decode(data, allowMalformed: true));
        }
      },
      onDone: () => _handleConnectionClosed(connection),
      onError: (Object error) => _handleConnectionFailure(connection, error),
      cancelOnError: false,
    );
    widget.session.termSubscription = subscription;

    try {
      await connection.markReady();
    } catch (error) {
      _handleConnectionFailure(connection, error);
      return;
    }

    if (!mounted ||
        !identical(_connection, connection) ||
        connection.isClosed) {
      return;
    }

    _connected = true;
    widget.session.isConnected = true;
    widget.session.error = null;
    _controller.markConnected();
    if (_controller.cancelRequested) {
      _sendControl('input_cancelled');
    }
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted || !identical(_connection, connection)) return;
      connection.send(
        '\x01${_terminal.viewWidth > 0 ? _terminal.viewWidth : 80},'
        '${_terminal.viewHeight > 0 ? _terminal.viewHeight : 30}',
      );
    });
  }

  void _handleConnectionClosed(ScriptConnection connection) {
    if (!mounted || !identical(_connection, connection)) return;
    final code = connection.closeCode ?? 0;
    final reason = connection.closeReason?.trim() ?? '';
    final message = (code >= 4000 && reason.isNotEmpty)
        ? reason
        : (code == 1000 || code == 1005 || code == 0
              ? 'The server closed the script connection.'
              : 'Connection to the script was lost.');
    _handleConnectionFailure(connection, message);
  }

  void _handleConnectionFailure(ScriptConnection connection, Object error) {
    if (!mounted || !identical(_connection, connection)) return;
    if (identical(_failedConnection, connection)) return;
    _failedConnection = connection;
    _connected = false;
    widget.session.isConnected = false;
    final subscription = widget.session.termSubscription;
    widget.session.termSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    if (identical(_connection, connection)) _connection = null;
    connection.markClosed();
    unawaited(connection.close());

    final message = error is String
        ? error
        : friendlyApiError(
            error,
            fallback: 'Connection to the script was lost.',
          );
    widget.session.error = message;
    _controller.markDisconnected(message: message);
    // Prompts are no longer answerable, but an open summary/table/msgbox is
    // still readable and may contain the script's final result.
    if (_activeSheetRequest?.isPrompt != false) _dismissActiveSheet();
  }

  // --- Protocol events -----------------------------------------------------

  void _handleEvent(ScriptEvent event) {
    if (!mounted) return;
    _controller.handleEvent(event);

    if (event is ScriptPromptEvent ||
        event is ScriptSummaryEvent ||
        event is ScriptTableEvent ||
        event is ScriptMessageBoxEvent) {
      _presentNextSheetIfAllowed();
      return;
    }

    if (event is ScriptEndEvent || event is ScriptErrorEvent) {
      // Prompts can no longer be answered. Informational sheets stay open so
      // a final summary/table/msgbox is not destroyed by the end marker.
      if (_activeSheetRequest?.isPrompt == true) {
        _dismissActiveSheet();
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _presentNextSheetIfAllowed(),
        );
      } else {
        _presentNextSheetIfAllowed();
      }
    }
  }

  // --- Sheets --------------------------------------------------------------

  void _presentNextSheetIfAllowed() {
    if (!mounted || !widget.isVisible || _sheetShowing || _closing) return;
    final pending = _controller.pendingSheets;
    if (pending.isEmpty) return;
    _presentSheet(pending.first);
  }

  void _presentSheet(ScriptSheetRequest request) {
    _sheetShowing = true;
    _activeSheetRequest = request;
    final generation = ++_sheetGeneration;
    final navigator = Navigator.of(context);
    final baseRoute = ModalRoute.of(context);
    Future<ScriptSheetResult?> future;
    if (request.prompt != null) {
      future = showScriptPromptSheet(context, request.prompt!);
    } else if (request.summary != null) {
      future = showScriptSummarySheet(context, request.summary!);
    } else if (request.table != null) {
      future = showScriptTableSheet(context, request.table!);
    } else if (request.messageBox != null) {
      future = showScriptMessageSheet(context, request.messageBox!);
    } else {
      _sheetShowing = false;
      _controller.removeSheet(request);
      _presentNextSheetIfAllowed();
      return;
    }

    _popActiveSheet = () {
      if (!navigator.mounted) return;
      if (baseRoute == null) {
        if (navigator.canPop()) navigator.pop();
        return;
      }
      // Pop any route stacked above the sheet (for example the stop
      // confirmation) and then the sheet itself.
      navigator.popUntil((route) => route == baseRoute || route.isFirst);
    };

    future.then((result) {
      if (!mounted || generation != _sheetGeneration) return;
      _popActiveSheet = null;
      _activeSheetRequest = null;
      _sheetShowing = false;
      if (result != null) {
        _handleSheetResult(request, result);
        _controller.removeSheet(request);
      }
      // A `null` result means the sheet was dismissed programmatically
      // (session became invisible or the script ended). Keep the request
      // queued in the latter case; the controller clears it on end/disconnect.
      _presentNextSheetIfAllowed();
    });
  }

  void _dismissActiveSheet() {
    final pop = _popActiveSheet;
    if (pop == null) return;
    _sheetGeneration++;
    _popActiveSheet = null;
    _activeSheetRequest = null;
    _sheetShowing = false;
    pop();
  }

  void _handleSheetResult(
    ScriptSheetRequest request,
    ScriptSheetResult result,
  ) {
    switch (result) {
      case ScriptInputResult(:final value) when request.prompt != null:
        if (_controller.isTerminal) break;
        _sendControl('input_response', {
          'variable': request.prompt!.variable,
          'value': value,
        });
      case ScriptClosedResult()
          when request.summary != null && !_controller.isTerminal:
        _sendControl('input_response', {
          'variable': 'NEXTERM_SUMMARY_RESULT',
          'value': 'closed',
        });
      case ScriptClosedResult()
          when request.table != null && !_controller.isTerminal:
        _sendControl('input_response', {
          'variable': 'NEXTERM_TABLE_RESULT',
          'value': 'closed',
        });
      case ScriptClosedResult()
          when request.messageBox != null && !_controller.isTerminal:
        _sendControl('input_response', {
          'variable': 'NEXTERM_MSGBOX_RESULT',
          'value': 'closed',
        });
      case ScriptCancelledResult():
        if (_controller.isTerminal) break;
        _controller.markCancelling();
        _sendControl('input_cancelled');
      case _:
        break;
    }
  }

  bool _sendControl(String type, [Map<String, dynamic> payload = const {}]) {
    final connection = _connection;
    if (connection == null) {
      _controller.markDisconnected(
        message: 'The script connection is not available.',
      );
      _dismissActiveSheet();
      return false;
    }
    if (!connection.isReady) {
      _handleConnectionFailure(
        connection,
        'The script connection is not ready.',
      );
      return false;
    }
    final sent = connection.send(
      scriptMagic + jsonEncode({'type': type, ...payload}),
    );
    if (!sent) {
      _handleConnectionFailure(
        connection,
        'Could not send a response to the script.',
      );
    }
    return sent;
  }

  // --- Actions -------------------------------------------------------------

  Future<void> _stopFromDock() async {
    if (!_controller.canStop) return;
    final stop = await confirmStopScript(context);
    if (!mounted || !stop) return;
    _controller.markCancelling();
    _dismissActiveSheet();
    _sendControl('input_cancelled');
  }

  Future<void> _closeSession() async {
    if (_closing) return;
    if (widget.session.isScriptRunning) {
      final close = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Close script session?'),
          content: const Text(
            'The running script will be interrupted and the session will be removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep running'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Close session'),
            ),
          ],
        ),
      );
      if (!mounted || close != true) return;
    }

    setState(() => _closing = true);
    try {
      await widget.sessionManager.closeSession(
        widget.session.sessionId,
        widget.token,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _closing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyApiError(
              error,
              fallback: 'Could not close the script session.',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _reconnect() async {
    if (!_controller.isDisconnected) return;
    _controller.resetForReconnect();
    _dismissActiveSheet();
    final reconnecting = await widget.sessionManager.reconnectScriptSession(
      token: widget.token,
      session: widget.session,
    );
    if (!mounted) return;
    if (!reconnecting) {
      _controller.markDisconnected(
        message: 'Could not reconnect to the script session.',
      );
      return;
    }
    _connection = null;
    await _attachConnection();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.terminalSettings.colorTheme;
    return ColoredBox(
      color: theme.background,
      child: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: TerminalView(
                _terminal,
                readOnly: true,
                autofocus: false,
                theme: theme.theme,
                textStyle: TerminalStyle(
                  fontSize: widget.terminalSettings.fontSize,
                  fontFamily: terminalNerdFontFamily,
                  fontFamilyFallback: terminalNerdFontFallback,
                  height: 1.2,
                ),
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 148),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: IgnorePointer(
                ignoring: _closing,
                child: ScriptExecutionDock(
                  controller: _controller,
                  serverName: widget.session.server.name,
                  onStop: _stopFromDock,
                  onClose: _closeSession,
                  onReconnect: _reconnect,
                ),
              ),
            ),
          ),
          if (_closing)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
