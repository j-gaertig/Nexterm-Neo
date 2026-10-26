import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../models/script_runtime.dart';
import '../../utils/script_protocol.dart';
import '../widgets/script/script_sheet_result.dart';

enum ScriptExecutionPhase {
  connecting,
  running,
  waitingForInput,
  cancelling,
  cancelled,
  completed,
  failed,
  disconnected,
}

class ScriptNoticeEntry {
  final ScriptNoticeKind kind;
  final String message;

  const ScriptNoticeEntry({required this.kind, required this.message});
}

/// Owns the lifecycle and protocol state of one script execution session.
///
/// Keeping this out of the renderer makes the tricky parts testable:
/// 1-based step bookkeeping, prompt queuing while the session is not visible,
/// bounded notice history, replay after reconnects, and the distinction
/// between "WebSocket closed" and "script completed".
class ScriptExecutionController extends ChangeNotifier {
  static const int maxNotices = 50;

  String _scriptName;
  final List<String> _steps = <String>[];
  int _currentStepNumber = 0;
  int? _failedStepIndex;
  int? _progressPercent;
  String _progressMessage = '';
  String? _errorMessage;
  int? _exitCode;
  ScriptExecutionPhase _phase = ScriptExecutionPhase.connecting;
  final List<ScriptSheetRequest> _pendingSheets = <ScriptSheetRequest>[];
  final ListQueue<ScriptNoticeEntry> _notices = ListQueue<ScriptNoticeEntry>();
  bool _cancelRequested = false;

  ScriptExecutionController({required String scriptName})
    : _scriptName = scriptName.isEmpty ? 'Script' : scriptName;

  String get scriptName => _scriptName;
  UnmodifiableListView<String> get steps => UnmodifiableListView(_steps);

  /// 1-based number of the active step, or `0` before the first step arrives.
  int get currentStepNumber => _currentStepNumber;
  int get stepCount => _steps.length;
  int? get failedStepIndex => _failedStepIndex;
  int? get progressPercent => _progressPercent;
  String get progressMessage => _progressMessage;
  String? get errorMessage => _errorMessage;
  int? get exitCode => _exitCode;
  ScriptExecutionPhase get phase => _phase;
  UnmodifiableListView<ScriptSheetRequest> get pendingSheets =>
      UnmodifiableListView(_pendingSheets);
  UnmodifiableListView<ScriptNoticeEntry> get notices =>
      UnmodifiableListView(_notices);

  bool get isCompleted => _phase == ScriptExecutionPhase.completed;
  bool get isCancelled => _phase == ScriptExecutionPhase.cancelled;
  bool get isFailed => _phase == ScriptExecutionPhase.failed;
  bool get isDisconnected => _phase == ScriptExecutionPhase.disconnected;
  bool get isTerminal =>
      isCompleted || isCancelled || isFailed || isDisconnected;
  bool get isRunning => _phase == ScriptExecutionPhase.running;
  bool get isWaitingForInput => _pendingSheets.isNotEmpty;
  bool get cancelRequested => _cancelRequested;
  bool get canStop =>
      _phase == ScriptExecutionPhase.running ||
      _phase == ScriptExecutionPhase.waitingForInput;

  String? get currentStepText {
    if (_currentStepNumber <= 0 || _currentStepNumber > _steps.length) {
      return null;
    }
    return _steps[_currentStepNumber - 1];
  }

  /// Explicit progress, forced to 100% once the script completed successfully.
  int? get displayProgress {
    if (isCompleted) return 100;
    return _progressPercent;
  }

  ScriptRuntimeState toRuntimeState() => ScriptRuntimeState(
    scriptName: _scriptName,
    status: switch (_phase) {
      ScriptExecutionPhase.connecting => ScriptSessionStatus.connecting,
      ScriptExecutionPhase.running =>
        _pendingSheets.isEmpty
            ? ScriptSessionStatus.running
            : ScriptSessionStatus.waitingForInput,
      ScriptExecutionPhase.waitingForInput =>
        ScriptSessionStatus.waitingForInput,
      ScriptExecutionPhase.cancelling => ScriptSessionStatus.cancelling,
      ScriptExecutionPhase.cancelled => ScriptSessionStatus.cancelled,
      ScriptExecutionPhase.completed => ScriptSessionStatus.completed,
      ScriptExecutionPhase.failed => ScriptSessionStatus.failed,
      ScriptExecutionPhase.disconnected => ScriptSessionStatus.disconnected,
    },
    currentStep: currentStepText,
    currentStepNumber: _currentStepNumber,
    stepCount: _steps.length,
    progressPercent: displayProgress,
    progressMessage: _progressMessage,
    error: _errorMessage,
    exitCode: _exitCode,
  );

  void handleEvent(ScriptEvent event) {
    switch (event) {
      case ScriptStartEvent(:final name):
        if (name.isNotEmpty) _scriptName = name;
        if (_phase == ScriptExecutionPhase.connecting) {
          _phase = ScriptExecutionPhase.running;
        }
      case ScriptStepEvent(:final number, :final description):
        if (isTerminal) return;
        if (number < 1) return;
        while (_steps.length < number) {
          _steps.add('Step ${_steps.length + 1}');
        }
        final trimmed = description.trim();
        _steps[number - 1] = trimmed.isEmpty ? 'Step $number' : trimmed;
        _currentStepNumber = number;
        _progressPercent = null;
        _progressMessage = '';
        _failedStepIndex = null;
        if (_phase != ScriptExecutionPhase.cancelling) {
          _phase = _pendingSheets.isEmpty
              ? ScriptExecutionPhase.running
              : ScriptExecutionPhase.waitingForInput;
        }
      case ScriptPromptEvent prompt:
        if (isTerminal || _cancelRequested) return;
        _pendingSheets.add(ScriptSheetRequest(prompt: prompt));
        _phase = ScriptExecutionPhase.waitingForInput;
      case ScriptSummaryEvent summary:
        if (isTerminal) return;
        _pendingSheets.add(ScriptSheetRequest(summary: summary));
        _phase = ScriptExecutionPhase.waitingForInput;
      case ScriptTableEvent table:
        if (isTerminal) return;
        _pendingSheets.add(ScriptSheetRequest(table: table));
        _phase = ScriptExecutionPhase.waitingForInput;
      case ScriptMessageBoxEvent messageBox:
        if (isTerminal) return;
        _pendingSheets.add(ScriptSheetRequest(messageBox: messageBox));
        _phase = ScriptExecutionPhase.waitingForInput;
      case ScriptNoticeEvent notice:
        if (isTerminal) return;
        if (notice.message.trim().isEmpty) return;
        if (_notices.length >= maxNotices) _notices.removeFirst();
        _notices.add(
          ScriptNoticeEntry(kind: notice.kind, message: notice.message.trim()),
        );
        if (_phase == ScriptExecutionPhase.connecting) {
          _phase = ScriptExecutionPhase.running;
        }
      case ScriptProgressEvent(:final percentage, :final message):
        if (isTerminal) return;
        _progressPercent = percentage.clamp(0, 100);
        _progressMessage = message;
        if (_phase == ScriptExecutionPhase.connecting) {
          _phase = ScriptExecutionPhase.running;
        }
      case ScriptEndEvent(:final success, :final exitCode):
        if (isTerminal) return;
        _exitCode = exitCode;
        _removeUnanswerableSheets();
        if (_phase == ScriptExecutionPhase.cancelling || _cancelRequested) {
          _failedStepIndex = null;
          _errorMessage = null;
          _phase = ScriptExecutionPhase.cancelled;
          break;
        }
        _failedStepIndex = success
            ? null
            : (_currentStepNumber > 0 ? _currentStepNumber - 1 : null);
        _progressPercent = success ? 100 : _progressPercent;
        _errorMessage = success ? null : 'Script exited with code $exitCode';
        _phase = success
            ? ScriptExecutionPhase.completed
            : ScriptExecutionPhase.failed;
      case ScriptErrorEvent():
        if (isTerminal) return;
        _removeUnanswerableSheets();
        if (_phase == ScriptExecutionPhase.cancelling || _cancelRequested) {
          _failedStepIndex = null;
          _errorMessage = null;
          _phase = ScriptExecutionPhase.cancelled;
          break;
        }
        _failedStepIndex = _currentStepNumber > 0
            ? _currentStepNumber - 1
            : null;
        _errorMessage = 'The script reported an error';
        _phase = ScriptExecutionPhase.failed;
    }
    notifyListeners();
  }

  void removeSheet(ScriptSheetRequest request) {
    final removed = _pendingSheets.remove(request);
    if (!removed) return;
    if (_pendingSheets.isEmpty &&
        _phase == ScriptExecutionPhase.waitingForInput) {
      _phase = ScriptExecutionPhase.running;
    }
    notifyListeners();
  }

  void markConnected() {
    if (_phase == ScriptExecutionPhase.connecting) {
      _phase = ScriptExecutionPhase.running;
      notifyListeners();
    }
  }

  void _removeUnanswerableSheets() {
    _pendingSheets.removeWhere((request) => !request.isInformational);
  }

  void markCancelling() {
    if (isTerminal) return;
    _cancelRequested = true;
    _pendingSheets.clear();
    _phase = ScriptExecutionPhase.cancelling;
    notifyListeners();
  }

  void markDisconnected({String? message}) {
    if (isTerminal) return;
    _pendingSheets.clear();
    _phase = ScriptExecutionPhase.disconnected;
    if (message != null && message.trim().isNotEmpty) {
      _errorMessage = message.trim();
    } else {
      _errorMessage ??= 'Connection to the script was lost';
    }
    notifyListeners();
  }

  /// Clears all replayable state before reattaching the WebSocket. The server
  /// replays the full script event history on the new connection.
  void resetForReconnect() {
    _steps.clear();
    _currentStepNumber = 0;
    _failedStepIndex = null;
    _progressPercent = null;
    _progressMessage = '';
    _errorMessage = null;
    _exitCode = null;
    _pendingSheets.clear();
    _notices.clear();
    _phase = _cancelRequested
        ? ScriptExecutionPhase.cancelling
        : ScriptExecutionPhase.connecting;
    notifyListeners();
  }
}
