import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:kterm/kterm.dart';
import 'package:web_socket_channel/io.dart';

import '../../services/session_manager.dart';
import '../../utils/app_icons.dart';
import '../../utils/script_protocol.dart';
import '../../utils/terminal_font.dart';
import '../../utils/terminal_graphics.dart';
import '../../utils/terminal_image_fetch.dart';
import '../widgets/script/script_message_sheet.dart';
import '../widgets/script/script_overlay.dart';
import '../widgets/script/script_prompt_sheet.dart';
import '../widgets/script/script_summary_sheet.dart';
import '../widgets/script/script_table_sheet.dart';
import '../widgets/script/script_sheet_result.dart';

/// Renders a script execution session on `/ws/term`. Mirrors the web
/// `ScriptRenderer`: raw terminal output streams into a terminal behind the
/// overlay, `\x1F` control messages drive the step/progress overlay and the
/// modal sheets. No auto-reconnect — script sessions are never retried
/// (web `ReconnectPolicy`).
class ScriptRenderer extends StatefulWidget {
  final AppSession session;
  final String token;
  final SessionManager sessionManager;

  const ScriptRenderer({
    super.key,
    required this.session,
    required this.token,
    required this.sessionManager,
  });

  @override
  State<ScriptRenderer> createState() => _ScriptRendererState();
}

class _ScriptRendererState extends State<ScriptRenderer> {
  Terminal get _terminal => widget.session.terminal!;
  IOWebSocketChannel? get _channel => widget.session.termChannel;

  late final ScriptStreamParser _parser;
  late final TerminalGraphicsProcessor _graphics;

  String _scriptName = '';
  List<String?> _steps = const ['Initializing...'];
  int _currentStep = 1;
  int? _failedStep;
  bool _isCompleted = false;
  int? _currentProgress;
  String? _errorMessage;

  /// One modal sheet at a time; further prompts queue (web `promptQueue`).
  ScriptSheetRequest? _activeSheet;
  final List<ScriptSheetRequest> _sheetQueue = [];
  bool _sheetShowing = false;
  VoidCallback? _popActiveSheet;

  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _scriptName = widget.session.scriptName ?? 'Script';
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
      onEvent: (event) => _handleEvent(event),
    );
    _terminal.onResize = (w, h, _, __) {
      if (mounted && _connected) {
        _channel?.sink.add('\x01$w,$h');
      }
    };
    _subscribe();
  }

  void _subscribe() {
    if (widget.session.termSubscription != null) {
      _connected = widget.session.isConnected;
      return;
    }
    widget.session.termSubscription = _channel?.stream.listen(
      (data) {
        if (!mounted) return;
        if (data is String) {
          _parser.processChunk(data);
        } else if (data is List<int>) {
          // Server sends text frames; byte frames are still decoded.
          _parser.processChunk(utf8.decode(data, allowMalformed: true));
        }
      },
      onDone: _onChannelClosed,
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _connected = false;
          _errorMessage = 'Script error: $error';
          _failedStep ??= _currentStep;
        });
        widget.session.isConnected = false;
      },
    );
    setState(() => _connected = true);
    widget.session.isConnected = true;

    // Size handshake, like `TerminalRenderer._setupTerminal`.
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _channel != null) {
        _channel?.sink.add(
          '\x01${_terminal.viewWidth > 0 ? _terminal.viewWidth : 80},${_terminal.viewHeight > 0 ? _terminal.viewHeight : 30}',
        );
      }
    });
  }

  @override
  void dispose() {
    _graphics.dispose();
    _parser.discardPending();
    _terminal.onResize = null;
    if (_sheetShowing && _popActiveSheet != null) {
      final pop = _popActiveSheet;
      _popActiveSheet = null;
      _sheetShowing = false;
      pop?.call();
    }
    super.dispose();
  }

  void _onChannelClosed() {
    if (!mounted) return;
    widget.session.isConnected = false;
    final code = _channel?.closeCode ?? 0;
    final reason = _channel?.closeReason ?? '';
    setState(() {
      _connected = false;
      if (code >= 4000 && reason.isNotEmpty) {
        _errorMessage = reason;
        _failedStep ??= _currentStep;
        _isCompleted = true;
      } else if (code != 1000 && code != 1005 && !_isCompleted) {
        _errorMessage = 'Script closed unexpectedly';
        _failedStep ??= _currentStep;
        _isCompleted = true;
      } else {
        _isCompleted = true;
      }
    });
  }

  // --- control message handling -------------------------------------------

  void _handleEvent(ScriptEvent event) {
    if (!mounted) return; // Late stream events after session close.
    switch (event) {
      case ScriptStartEvent(:final name):
        setState(() => _scriptName = name.isNotEmpty ? name : _scriptName);
      case ScriptStepEvent(:final number, :final description):
        setState(() {
          final steps = List<String?>.of(_steps);
          if (steps.length <= number) {
            while (steps.length < number) {
              steps.add(null);
            }
            steps.add(description);
          }
          _steps = steps;
          _currentStep = number + 1;
          _currentProgress = null;
        });
      case ScriptPromptEvent():
      case ScriptSummaryEvent():
      case ScriptTableEvent():
      case ScriptMessageBoxEvent():
        _queueOrShowSheet(_requestFor(event));
      case ScriptNoticeEvent(:final kind, :final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message, style: const TextStyle(color: Colors.white)),
            backgroundColor: switch (kind) {
              ScriptNoticeKind.warning => Colors.orange.shade800,
              ScriptNoticeKind.info => Theme.of(context).colorScheme.secondary,
              ScriptNoticeKind.success => Colors.green.shade700,
            },
            behavior: SnackBarBehavior.floating,
          ),
        );
      case ScriptProgressEvent(:final percentage):
        setState(() => _currentProgress = percentage);
      case ScriptEndEvent(:final success):
        setState(() {
          _isCompleted = true;
          _failedStep = success ? null : _currentStep;
        });
      case ScriptErrorEvent():
        setState(() => _failedStep ??= _currentStep);
    }
  }

  ScriptSheetRequest _requestFor(ScriptEvent event) => switch (event) {
    ScriptPromptEvent prompt => ScriptSheetRequest(prompt: prompt),
    ScriptSummaryEvent summary => ScriptSheetRequest(summary: summary),
    ScriptTableEvent table => ScriptSheetRequest(table: table),
    ScriptMessageBoxEvent messageBox => ScriptSheetRequest(
      messageBox: messageBox,
    ),
    _ => const ScriptSheetRequest(),
  };

  // --- sheets --------------------------------------------------------------

  void _queueOrShowSheet(ScriptSheetRequest request) {
    if (_activeSheet != null) {
      _sheetQueue.add(request);
      return;
    }
    _activeSheet = request;
    _presentActiveSheet();
  }

  void _presentActiveSheet() {
    if (!mounted || _sheetShowing || _activeSheet == null) return;
    _sheetShowing = true;
    final request = _activeSheet!;
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
      _activeSheet = null;
      _showNextSheet();
      return;
    }
    _popActiveSheet = () => Navigator.of(context, rootNavigator: true).pop();
    future.then((result) {
      _popActiveSheet = null;
      _sheetShowing = false;
      if (mounted) {
        _handleSheetResult(request, result);
      }
      _activeSheet = null;
      _showNextSheet();
    });
  }

  void _showNextSheet() {
    if (!mounted) return;
    if (_sheetQueue.isEmpty) return;
    setState(() => _activeSheet = _sheetQueue.removeAt(0));
    _presentActiveSheet();
  }

  void _handleSheetResult(
    ScriptSheetRequest request,
    ScriptSheetResult? result,
  ) {
    if (result == null) return; // Dismissed programmatically (e.g. cancel).
    switch (result) {
      case ScriptInputResult(:final value) when request.prompt != null:
        _sendControl('input_response', {
          'variable': request.prompt!.variable,
          'value': value,
        });
      case ScriptClosedResult() when request.summary != null:
        _sendControl('input_response', {
          'variable': 'NEXTERM_SUMMARY_RESULT',
          'value': 'closed',
        });
      case ScriptClosedResult() when request.table != null:
        _sendControl('input_response', {
          'variable': 'NEXTERM_TABLE_RESULT',
          'value': 'closed',
        });
      case ScriptClosedResult() when request.messageBox != null:
        _sendControl('input_response', {
          'variable': 'NEXTERM_MSGBOX_RESULT',
          'value': 'closed',
        });
      case ScriptCancelledResult():
        _sendControl('input_cancelled');
      case _:
        break;
    }
  }

  void _sendControl(String type, [Map<String, dynamic> payload = const {}]) {
    _channel?.sink.add(scriptMagic + jsonEncode({'type': type, ...payload}));
  }

  // --- overlay actions -----------------------------------------------------

  void _cancelFromOverlay() {
    _sendControl('input_cancelled');
    if (_sheetShowing && _activeSheet?.isPrompt == true) {
      // Mirrors web `handleCancel`: closes the open input dialog without
      // sending a response from the dialog itself.
      _popActiveSheet?.call();
    }
  }

  Future<void> _closeSession() async {
    await widget.sessionManager.closeSession(
      widget.session.sessionId,
      widget.token,
    );
  }

  // --- step visuals (port of web `getTypeByIndex`) --------------------------

  StepVisual _visualForStep(int index) {
    final failedStep = _failedStep;
    if (failedStep != null && index == failedStep - 1) return StepVisual.error;
    if (failedStep != null && index > failedStep - 1) return StepVisual.skip;
    if (index < _currentStep - 1) return StepVisual.success;
    if (index == _currentStep - 1) {
      if (_isCompleted && index == _steps.length - 1) return StepVisual.success;
      return _currentProgress != null
          ? StepVisual.progress
          : StepVisual.loading;
    }
    return StepVisual.pending;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: TerminalThemes.defaultTheme.background,
            child: TerminalView(
              _terminal,
              readOnly: true,
              autofocus: false,
              textStyle: TerminalStyle(
                fontSize: 13,
                fontFamily: terminalNerdFontFamily,
                fontFamilyFallback: terminalNerdFontFallback,
                height: 1.2,
              ),
              padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
            ),
          ),
        ),
        if (_errorMessage != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: cs.errorContainer,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        AppIcons.alertCircle,
                        size: 18,
                        color: cs.onErrorContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            top: false,
            child: ScriptOverlay(
              scriptName: _scriptName,
              steps: _steps,
              failedStep: _failedStep,
              isCompleted: _isCompleted,
              currentStep: _currentStep,
              currentProgress: _currentProgress,
              visualForStep: _visualForStep,
              onCancel: _cancelFromOverlay,
              onClose: _isCompleted ? _closeSession : null,
            ),
          ),
        ),
      ],
    );
  }
}
